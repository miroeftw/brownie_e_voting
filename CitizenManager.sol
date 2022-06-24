// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "./ElectionManager.sol";

contract CitizenManager is ElectionManager {
    struct Citizen {
        uint256 NIP; //Numéro d'identification personnel ou autre...
        address citizenAddress;
        uint8 circonscription; //Les différentes circonscriptions seront numérotées.
    }

    //[electionID][citizenAddress]=true or false
    mapping(uint256 => mapping(address => bool)) hasRigthToVote;
    mapping(uint256 => mapping(address => bool)) hasVoted;

    modifier canVote(uint256 _electionID) {
        require(
            hasRigthToVote[_electionID][msg.sender] == true,
            "You aren't on the electoral list"
        );
        require(
            hasVoted[_electionID][msg.sender] == false,
            "You've already voted on this election"
        );
        _;
    }

    event HasVoted(address Voter, uint256 _electionID);
    event GotAVote(uint256 _candidateId, uint256 _electionID);

    /*Les votes vont remplacer nos transactions.
     *Vote est un jeton contenant:
     *voteID(hash),
     *electionID,
     *receiver,
     *circonscription,
     *signature,
     *number of vote(the candidate that delegates their votes will have more than 1 here)
     */
    //On va créer un candidat par défaut qui prendra les votes blancs
    function vote(
        uint256 _candidateId,
        uint256 _electionID,
        uint8 _circonscription
    ) external payable canVote(_electionID) electionOngoing(_electionID) {
        while (
            elections[_electionID].candidates[_candidateId].delegated = true
        ) {
            for (
                uint256 i = 0;
                i < elections[_electionID].candidates.length;
                i++
            ) {
                if (
                    elections[_electionID].candidates[i].candidateAddress ==
                    elections[_electionID]
                        .candidates[_candidateId]
                        .candidateAddress &&
                    i != _candidateId
                ) {
                    _candidateId = i;
                }
            }
        }
        elections[_electionID].candidates[_candidateId].votesByCirconscription[
                _circonscription
            ]++; //check length later
        elections[_electionID].totalVotes++;
        emit GotAVote(_candidateId, _electionID);

        hasVoted[_electionID][msg.sender] = true;
        emit HasVoted(msg.sender, _electionID);
    }
}
