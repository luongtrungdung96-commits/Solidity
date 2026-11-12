// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "test/test.sol";
import {console} from "hardhat/console.sol";


import {SmartRoscaVault} from "../contracts/SmartRoscaVault.sol";

contract SmartRoscaVaultTest is Test {
    SmartRoscaVault public vault;

    address player1 = address(0x111);
    address player2 = address(0x222);
    address player3 = address(0x333);
    address player4 = address(0x444);

    function setUp() public {
        vault = new SmartRoscaVault(0.1 ether, 4, 1 days, 7 days);

        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(player3, 10 ether);
        vm.deal(player4, 10 ether);
    }

    function test_FullRound1Flow() public {
        console.log("--- BUOC 1: 4 NGUOI DANG KY THAM GIA ---");
        vm.prank(player1); vault.join();
        vm.prank(player2); vault.join();
        vm.prank(player3); vault.join();
        vm.prank(player4); vault.join();

        console.log("Trang thai quy (1 = Active):", uint256(vault.currentState()));
        assertEq(uint256(vault.currentState()), 1);

        console.log("--- BUOC 2: CA 4 NGUOI DONG 0.1 AVAX ---");
        vm.prank(player1); vault.deposit{value: 0.1 ether}();
        vm.prank(player2); vault.deposit{value: 0.1 ether}();
        vm.prank(player3); vault.deposit{value: 0.1 ether}();
        vm.prank(player4); vault.deposit{value: 0.1 ether}();

        console.log("Tong quy hien tai (wei):", vault.roundPot());
        assertEq(vault.roundPot(), 0.4 ether);

        console.log("--- BUOC 3: CHOT SO & CHIA TIEN CHO PLAYER 1 ---");
        vault.settleRound();
        assertEq(vault.claimable(player1), 0.4 ether);

        console.log("--- BUOC 4: PLAYER 1 RUT TIEN VE VI ---");
        uint256 balanceBefore = player1.balance;
        vm.prank(player1);
        vault.claim();
        uint256 balanceAfter = player1.balance;

        console.log("So du Player 1 tang them (wei):", balanceAfter - balanceBefore);
        assertEq(balanceAfter - balanceBefore, 0.4 ether);
    }
}
