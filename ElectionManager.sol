// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CandidateManager.sol";

contract ElectionManager is Ownable {
    using SafeMath for uint256;

    /*
    UNI2: SCrutin uninominal majoritaire à deux tour
    PROP: Scrutin proportionnel plurinominal
    */
    enum Scrutin {
        UNI2,
        PROP
    }

    struct Election {
        string name;
        Scrutin scrutin;
        Candidate[] candidates;
        uint256 startTime;
        uint256 endTime;
        uint8 nbCirconscription;
        uint8[] seatsByCirconscription;
        uint256 totalVotes;
    }

    enum CandidateType {
        INDIVIDUAL,
        PARTY
    }

    struct Candidate {
        string name;
        address candidateAddress;
        uint256[] votesByCirconscription;
        CandidateType typeCandidate;
        bool delegated;
    }

    Election[] public elections;

    //Comment remplir pour chaque election?
    mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256))) _manualVotesByCirconscription;
    //_manualVotesByCirconscription[candidateID][circonscriptionNumber] = manualVotes

    modifier electionNotStarted(uint256 _electionID) {
        require(
            elections[_electionID].startTime >= block.timestamp,
            "This election has already started"
        );
        _;
    }

    modifier electionOngoing(uint256 _electionID) {
        require(
            elections[_electionID].startTime <= block.timestamp,
            "This election hasn't started yet"
        );
        require(
            elections[_electionID].endTime >= block.timestamp,
            "This election has ended started"
        );
        _;
    }

    modifier electionEnded(uint256 _electionID) {
        require(
            elections[_electionID].endTime > block.timestamp,
            "This election has ended yet"
        );
        _;
    }

    event NewElection(
        uint256 electionID,
        string _name,
        Scrutin _scrutin,
        uint256 _startTime,
        uint256 _endTime,
        uint8 _nbCirconscription
    );

    event GotManualVotes(
        uint256 _candidateId,
        uint256 votesNumber,
        uint256 _electionID,
        uint8 circonscription
    );
    event NumberOfManualsVotes(uint256 numberOfManualsVotes);

    event ChaosWinner(
        uint256 electionID,
        string _electionName,
        Scrutin _scrutin,
        uint256 _candidateId,
        string _candidateName,
        uint256 _votes
    );
    event Winner(
        uint256 electionID,
        string _electionName,
        Scrutin _scrutin,
        uint256 _candidateId,
        string _candidateName,
        uint256 _votes
    );
    event RetainedCandidatesAfterNationalScreening(
        Candidate[] remainingCandidates
    );
    event SelectedList(
        uint256 _electionID,
        uint8 circonscription,
        uint256[] selectedLists
    );
    event RepartitionSeatsForCirconscription(
        uint256 _electionID,
        uint256 circonscription,
        uint256[] selectedLists,
        uint8[] seatsbyLists
    );

    function addElection(
        string memory _name,
        Scrutin _scrutin,
        uint256 _startTime,
        uint256 _endTime,
        uint8 _nbCirconscription,
        address _blankVotesAddress
    ) external onlyOwner {
        require(
            _startTime >= block.timestamp,
            "The starting time inputed is unacceptable"
        );
        require(
            _startTime < _endTime,
            "The ending time inputed is unacceptable"
        );

        uint256 electionID = elections.length;

        elections[electionID].name = _name;
        elections[electionID].scrutin = _scrutin;
        elections[electionID].startTime = _startTime;
        elections[electionID].endTime = _endTime;
        elections[electionID].nbCirconscription = _nbCirconscription;
        elections[electionID].seatsByCirconscription = new uint8[](0);
        elections[electionID].totalVotes = 0;

        //Blank Votes Candidates
        CandidateType candidateType;
        if (_scrutin == Scrutin.UNI2) {
            candidateType = CandidateType.INDIVIDUAL;
        } else {
            candidateType = CandidateType.PARTY;
        }

        elections[electionID].candidates.push(
            Candidate(
                "Blank Votes",
                _blankVotesAddress,
                new uint256[](_nbCirconscription),
                candidateType,
                false
            )
        );
        emit NewElection(
            electionID,
            _name,
            _scrutin,
            _startTime,
            _endTime,
            _nbCirconscription
        );
    }

    function tallying(uint256 _electionID)
        external
        onlyOwner
        electionEnded(_electionID)
    {
        if (elections[_electionID].scrutin == Scrutin.UNI2) {
            //Scrutin uninominal majoritaire à deux tours
            uint256 pos = 0;
            uint256 votesPos = 0;
            bool chaosWin;
            (chaosWin, pos, votesPos) = _chaosWinUNI2(_electionID);
            if (chaosWin == true) {
                emit ChaosWinner(
                    _electionID,
                    elections[_electionID].name,
                    elections[_electionID].scrutin,
                    pos,
                    elections[_electionID].candidates[pos].name,
                    votesPos
                );
            } else {
                (pos, votesPos) = _winUNI2(_electionID, 0);
                emit Winner(
                    _electionID,
                    elections[_electionID].name,
                    elections[_electionID].scrutin,
                    pos,
                    elections[_electionID].candidates[pos].name,
                    votesPos
                );

                if (elections[_electionID].candidates.length != 3) {
                    //i.e plus de 2 candidats
                    (pos, votesPos) = _winUNI2(_electionID, pos);
                    emit Winner(
                        _electionID,
                        elections[_electionID].name,
                        elections[_electionID].scrutin,
                        pos,
                        elections[_electionID].candidates[pos].name,
                        votesPos
                    );
                }
            }
        } else {
            //Scrutin proportionnel plurinominal: https://fr.wikipedia.org/wiki/Scrutin_proportionnel_plurinominal#M%C3%A9thodes_au_plus_fort_reste
            uint8 seuilElectoral = 10; //10%

            //Supprimer toutes les listes qui n'ont pas atteint le seuil électoral au niveau national
            Candidate[] memory remainingCandidates = _deleteLoosers(
                _electionID,
                seuilElectoral
            );
            emit RetainedCandidatesAfterNationalScreening(remainingCandidates);

            //Quotient électoral
            uint256 quotientElectoral = _calculQuotientElectoral(_electionID);

            //Traitement par circonscription
            for (
                uint8 circonscription = 0;
                circonscription <= elections[_electionID].nbCirconscription;
                circonscription++
            ) {
                //Supprimer toutes les listes qui n'ont pas atteint le seuil électoral au niveau des circonscriptions
                //Incices des listes retenues
                uint256[] memory selectedLists = _deleteLoosersCirconscription(
                    _electionID,
                    remainingCandidates,
                    circonscription,
                    seuilElectoral
                );
                emit SelectedList(_electionID, circonscription, selectedLists);

                //Méthode utilisant le quotient de Hare
                uint8[]
                    memory seatsbyLists = _repartitionSeatsForCirconscription(
                        _electionID,
                        remainingCandidates,
                        circonscription,
                        selectedLists,
                        quotientElectoral
                    );
                emit RepartitionSeatsForCirconscription(
                    _electionID,
                    circonscription,
                    selectedLists,
                    seatsbyLists
                );
            }
        }
    }

    // Scrutin uninominal à 2 tours
    //Plus de 50% du suffrage exprimé: Victoire par chaos
    function _chaosWinUNI2(uint256 _electionID)
        internal
        view
        onlyOwner
        electionEnded(_electionID)
        returns (
            bool chaosWin,
            uint256 pos,
            uint256 votesPos
        )
    {
        pos = 0;
        chaosWin = false;
        votesPos = 0;
        for (pos = 1; pos < elections[_electionID].candidates.length; pos++) {
            if (elections[_electionID].candidates[pos].delegated == false) {
                votesPos = 0;
                for (
                    uint8 j = 0;
                    j < elections[_electionID].nbCirconscription;
                    j++
                ) {
                    votesPos += elections[_electionID]
                        .candidates[pos]
                        .votesByCirconscription[j];
                }
                if (votesPos > elections[_electionID].totalVotes / 2) {
                    chaosWin = true;
                    break;
                }
            }
        }
    }

    //Plus grand nombre de voix receuillies
    function _winUNI2(uint256 _electionID, uint256 _ignorePos)
        internal
        view
        onlyOwner
        electionEnded(_electionID)
        returns (uint256 pos, uint256 votesPos)
    {
        votesPos = 0;
        uint256 votesI;
        for (uint256 i = 1; i < elections[_electionID].candidates.length; i++) {
            if (elections[_electionID].candidates[i].delegated == false) {
                votesI = 0;
                for (
                    uint8 j = 0;
                    j < elections[_electionID].nbCirconscription;
                    j++
                ) {
                    votesI += elections[_electionID]
                        .candidates[i]
                        .votesByCirconscription[j];
                }
                if (votesI > votesPos && i != _ignorePos) {
                    pos = i;
                    votesPos = votesI;
                }
            }
        }
    }

    //Scrutin proportionnel
    //Supprimer toutes les listes qui n'ont pas atteint le seuil électoral au niveau national
    function _deleteLoosers(uint256 _electionID, uint8 _seuilElectoral)
        internal
        view
        onlyOwner
        electionEnded(_electionID)
        returns (Candidate[] memory remainingCandidates)
    {
        remainingCandidates = elections[_electionID].candidates;
        for (uint256 i = 1; i < remainingCandidates.length; i++) {
            uint256 votesI = 0;
            for (
                uint8 j = 0;
                j < elections[_electionID].nbCirconscription;
                j++
            ) {
                votesI += remainingCandidates[i].votesByCirconscription[j];
            }
            if (
                votesI / elections[_electionID].totalVotes <
                _seuilElectoral / 100
            ) {
                remainingCandidates[i] = remainingCandidates[
                    remainingCandidates.length - 1
                ];
                delete (remainingCandidates[remainingCandidates.length - 1]);
                i--;
            }
        }
    }

    //Quotient électoral
    function _calculQuotientElectoral(uint256 _electionID)
        internal
        view
        onlyOwner
        electionEnded(_electionID)
        returns (uint256 quotientElectoral)
    {
        uint16 totalSeats;
        for (
            uint256 i = 0;
            i < elections[_electionID].seatsByCirconscription.length;
            i++
        ) {
            totalSeats += elections[_electionID].seatsByCirconscription[i];
        }
        quotientElectoral =
            (elections[_electionID].totalVotes * 100) /
            totalSeats;
        //Multiplié par une puissance de 10 et diviser à chaque utilisation pour garder les nombres après la virgule
    }

    //Traitement par circonscription
    //Calcul du total des votes de la circonscription
    function _totalVotesByCirconscription(
        uint256 _electionID,
        uint8 _circonscription
    )
        internal
        view
        onlyOwner
        electionEnded(_electionID)
        returns (uint256 totalVotesCirconscription)
    {
        for (uint256 i = 1; i < elections[_electionID].candidates.length; i++) {
            totalVotesCirconscription += elections[_electionID]
                .candidates[i]
                .votesByCirconscription[_circonscription];
        }
    }

    //Supprimer toutes les listes qui n'ont pas atteint le seuil électoral au niveau des circonscriptions
    function _deleteLoosersCirconscription(
        uint256 _electionID,
        Candidate[] memory remainingCandidates,
        uint8 _circonscription,
        uint8 _seuilElectoral
    )
        internal
        view
        onlyOwner
        electionEnded(_electionID)
        returns (uint256[] memory selectedLists)
    {
        for (uint256 i = 1; i < remainingCandidates.length; i++) {
            if (
                remainingCandidates[i].votesByCirconscription[
                    _circonscription
                ] /
                    _totalVotesByCirconscription(
                        _electionID,
                        _circonscription
                    ) <
                _seuilElectoral / 100
            ) {
                selectedLists[selectedLists.length] = i;
            }
        }
    }

    //Répartition des sièges utilisant le quotient de Hare
    function _repartitionSeatsForCirconscription(
        uint256 _electionID,
        Candidate[] memory remainingCandidates,
        uint8 _circonscription,
        uint256[] memory _selectedLists,
        uint256 _quotientElectoral
    )
        internal
        onlyOwner
        electionEnded(_electionID)
        returns (uint8[] memory seatsbyLists)
    {
        //*Premier tour
        for (uint256 i = 0; i < _selectedLists.length; i++) {
            while (
                remainingCandidates[_selectedLists[i]].votesByCirconscription[
                    _circonscription
                ] >= _quotientElectoral
            ) {
                remainingCandidates[_selectedLists[i]].votesByCirconscription[
                        _circonscription
                    ] -= _quotientElectoral;
                seatsbyLists[i]++;
                elections[_electionID].seatsByCirconscription[
                    _circonscription
                ]--;
            }
        }
        //*Second tour
        while (
            elections[_electionID].seatsByCirconscription[_circonscription] > 0
        ) {
            uint256 maxRemain = 0;
            for (uint256 i = 0; i < _selectedLists.length; i++) {
                if (
                    remainingCandidates[_selectedLists[i]]
                        .votesByCirconscription[_circonscription] >
                    elections[_electionID]
                        .candidates[_selectedLists[maxRemain]]
                        .votesByCirconscription[_circonscription]
                ) {
                    maxRemain = i;
                }
            }
            remainingCandidates[_selectedLists[maxRemain]]
                .votesByCirconscription[_circonscription] = 0;
            //J'ai fait comme ceci parceque je n'ai pas encore trouvé de cas où il faut un troisième tour.
            seatsbyLists[maxRemain]++;
            elections[_electionID].seatsByCirconscription[_circonscription]--;
        }
    }

    function addManualVotes(uint256 _electionID)
        external
        onlyOwner
        electionEnded(_electionID)
    {
        uint256 numberOfManualsVotes = 0;
        for (uint256 i = 0; i < elections[_electionID].candidates.length; i++) {
            uint256 candidateID = i;
            while (
                elections[_electionID].candidates[candidateID].delegated = true
            ) {
                for (
                    uint256 j = 0;
                    j < elections[_electionID].candidates.length;
                    j++
                ) {
                    if (
                        elections[_electionID].candidates[j].candidateAddress ==
                        elections[_electionID]
                            .candidates[candidateID]
                            .candidateAddress &&
                        j != candidateID
                    ) {
                        candidateID = j;
                    }
                }
            }
            for (
                uint8 circonscription = 0;
                circonscription <= elections[_electionID].nbCirconscription;
                circonscription++
            ) {
                elections[_electionID]
                    .candidates[candidateID]
                    .votesByCirconscription[
                        circonscription
                    ] += _manualVotesByCirconscription[_electionID][
                    candidateID
                ][circonscription];
                numberOfManualsVotes += _manualVotesByCirconscription[
                    _electionID
                ][candidateID][circonscription];
                elections[_electionID]
                    .totalVotes += _manualVotesByCirconscription[_electionID][
                    candidateID
                ][circonscription];
                emit GotManualVotes(
                    candidateID,
                    _manualVotesByCirconscription[_electionID][candidateID][
                        circonscription
                    ],
                    _electionID,
                    circonscription
                );
            }
        }
        emit NumberOfManualsVotes(numberOfManualsVotes);
    }
}
