// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Voting {
    mapping(string => uint) private candidateVotes;
    string[] private candidates;

    function vote(string calldata _candidateName) public {
        candidateVotes[_candidateName] += 1;
        bool exists;
        for (uint i = 0; i < candidates.length; i++) {
            if (keccak256(bytes(candidates[i])) == keccak256(bytes(_candidateName))) {
                exists = true;
                break;
            }
        }
        if (!exists) candidates.push(_candidateName);
    }

    function getVotes(string calldata _candidateName) public view  returns (uint) {
        return candidateVotes[_candidateName];
    }

    function resetVotes() public {
        for (uint i = 0; i < candidates.length; i++) {
            delete candidateVotes[candidates[i]];
        }
    }
}