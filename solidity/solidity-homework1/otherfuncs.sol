// SPDX-License-Identifier: MIT
pragma solidity ~0.8.20;

contract OhterFuncs {
    function reverseString(
        string memory _input
    ) public pure returns (string memory res) {
        bytes memory temp = bytes(_input);
        for (uint i = 0; i < temp.length / 2; i++) {
            (temp[i], temp[temp.length - i - 1]) = (
                temp[temp.length - i - 1],
                temp[i]
            );
        }
        res = string(temp);
    }

    function remanToInt(string memory roman) public pure returns (int) {
        uint256 result = 0;
        uint256 preVal = 0;

        for (uint256 i = bytes(roman).length; i > 0; i--) {
            bytes1 curChar = bytes(roman)[i - 1];
            uint256 curVal = _getRomanValue(curChar);

            if (curVal < preVal) {
                result -= curVal;
            } else {
                result += curVal;
            }
            preVal = curVal;
        }

        return int(result);
    }

    function _getRomanValue(bytes1 romanChar) private pure returns (uint256) {
        if (romanChar == "I") return 1;
        if (romanChar == "V") return 5;
        if (romanChar == "X") return 10;
        if (romanChar == "L") return 50;
        if (romanChar == "C") return 100;
        if (romanChar == "D") return 500;
        if (romanChar == "M") return 1000;

        revert("Invalid Roman numeral character");
    }

    function intToRoman(uint256 num) public pure returns (string memory) {
        require(num > 0 && num <= 3999, "Number must be between 1 and 3999");

        string[13] memory symbols = [
            "M",
            "CM",
            "D",
            "CD",
            "C",
            "XC",
            "L",
            "XL",
            "X",
            "IX",
            "V",
            "IV",
            "I"
        ];
        uint256[13] memory values = [
            uint256(1000),
            uint256(900),
            uint256(500),
            uint256(400),
            uint256(100),
            uint256(90),
            uint256(50),
            uint256(40),
            uint256(10),
            uint256(9),
            uint256(5),
            uint256(4),
            uint256(1)
        ];

        string memory result = "";

        for (uint256 i = 0; i < 13; i++) {
            while (num >= values[i]) {
                result = string(abi.encodePacked(result, symbols[i]));
                num -= values[i];
            }
        }

        return result;
    }

    function mergeSortedArrays(int[] memory arr1, int[] memory arr2) public pure returns (int[] memory) {
        uint len1 = arr1.length;
        uint len2 = arr2.length;
        uint totalLength = len1 + len2;

        int[] memory merged = new int[](totalLength);
        uint i = 0; // Pointer for arr1
        uint j = 0; // Pointer for arr2
        uint k = 0; // Pointer for merged array

        while (i < len1 && j < len2) {
            if (arr1[i] <= arr2[j]) {
                merged[k] = arr1[i];
                i++;
            } else {
                merged[k] = arr2[j];
                j++;
            }
            k++;
        }

        // Copy remaining elements from arr1 if any
        while (i < len1) {
            merged[k] = arr1[i];
            i++;
            k++;
        }

        // Copy remaining elements from arr2 if any
        while (j < len2) {
            merged[k] = arr2[j];
            j++;
            k++;
        }

        return merged;
    }

    /**
     * @dev Performs binary search on a sorted array
     * @param arr The sorted array to search
     * @param target The value to search for
     * @return The index of the target if found, -1 otherwise
     */
    function binarySearch(int[] memory arr, int target) public pure returns (int) {
        int left = 0;
        int right = int(arr.length) - 1;

        while (left <= right) {
            int mid = left + (right - left) / 2;

            if (arr[uint(mid)] == target) {
                return mid; // Target found
            } else if (arr[uint(mid)] < target) {
                left = mid + 1; // Search right half
            } else {
                right = mid - 1; // Search left half
            }
        }

        return -1; // Target not found
    }
}
