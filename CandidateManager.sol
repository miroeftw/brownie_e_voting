// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "./ElectionManager.sol";

contract CandidateManager is ElectionManager {
    modifier isCandidate(uint256 _candidateId, uint256 _electionID) {
        require(elections[_electionID].candidates.length > _candidateId);
        _;
    }

    event NewCandidate(
        uint256 candidateId,
        string name,
        CandidateType typeCandidate,
        uint256 electionID
    );
    event HasDelegated(
        address candidateDelegating,
        uint256 candidateId,
        uint256 electionID
    );

    function _addCandidate(
        uint256 _electionID,
        string memory _name,
        address _candidateAddress
    ) external onlyOwner electionNotStarted(_electionID) {
        uint256[] memory initVotesByCirconscription = new uint256[](
            elections[_electionID].nbCirconscription
        );

        if (elections[_electionID].scrutin == Scrutin.UNI2) {
            elections[_electionID].candidates.push(
                Candidate(
                    _name,
                    _candidateAddress,
                    initVotesByCirconscription,
                    CandidateType.INDIVIDUAL,
                    false
                )
            );
            uint256 candidateId = elections[_electionID].candidates.length - 1;
            emit NewCandidate(
                candidateId,
                _name,
                CandidateType.INDIVIDUAL,
                _electionID
            );
        } else {
            elections[_electionID].candidates.push(
                Candidate(
                    _name,
                    _candidateAddress,
                    initVotesByCirconscription,
                    CandidateType.PARTY,
                    false
                )
            );
            uint256 candidateId = elections[_electionID].candidates.length - 1;
            emit NewCandidate(
                candidateId,
                _name,
                CandidateType.PARTY,
                _electionID
            );
        }
    }

    function delegateVote(
        uint256 _myId,
        uint256 _candidateId,
        uint256 _electionID
    )
        external
        payable
        isCandidate(_myId, _electionID)
        isCandidate(_candidateId, _electionID)
        electionOngoing(_electionID)
    {
        require(
            elections[_electionID].candidates[_myId].candidateAddress ==
                msg.sender,
            "You aren't a candidate for this election"
        );
        /*Il faut un contr??le sur les d??l??gations.
         *Si quelqu'un donne ses voix ?? quelqu'un qui les lui avait donn?? par exemple ??a cr??erait une boucle infinie.
         *On va dire qu'un candidat ne peux d??l??guer ses voix qu'?? un candidat qui n'a pas encore d??l??gu?? ses voix.*/
        require(
            elections[_electionID].candidates[_candidateId].delegated == false,
            "The candidate chosen already delegated his voices. Please choose another one."
        );
        for (uint8 i = 0; i < elections[_electionID].nbCirconscription; i++) {
            elections[_electionID]
                .candidates[_candidateId]
                .votesByCirconscription[i] =
                elections[_electionID]
                    .candidates[_candidateId]
                    .votesByCirconscription[i] +
                elections[_electionID].candidates[_myId].votesByCirconscription[
                        i
                    ]; //check length later
            elections[_electionID].candidates[_myId].votesByCirconscription[
                    i
                ] = 0;
        }

        elections[_electionID].candidates[_myId].delegated = true;
        elections[_electionID].candidates[_myId].candidateAddress = elections[
            _electionID
        ].candidates[_candidateId].candidateAddress;
        emit HasDelegated(msg.sender, _candidateId, _electionID);
    }
}
