"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: KINN Stake Contract
// Version: 0.1.6 - use base, add delegate
// Requires Reach v0.1.11-rc7 (27cb9643) or later
// -----------------------------------------------

import {
  State as BaseState,
  Params as BaseParams,
  view,
  baseState,
  baseEvents
} from "@KinnFoundation/base#base-v0.1.11r4:interface.rsh";

// CONSTS

const SERIAL_VER = 0;

// FUNCS

const stakeState = (delegateAddr, token, tokenAmount, remoteCtc, staked = false, time = 0, secs = 0) => ({
  token,
  tokenAmount,
  remoteCtc,
  delegateAddr,
  staked,
  time,
  secs
});

// TYPES

export const StakeParams = Object({
  tokenAmount: UInt, // NFT token amount
  remoteCtc: Contract, // remote contract
});

const Params = Object({
  ...Object.fields(BaseParams),
  ...Object.fields(StakeParams),
});

export const StakeState = Struct([
  ["token", Token], // NFT token
  ["tokenAmount", UInt], // NFT token amount
  ["remoteCtc", Contract], // remote contract
  ["staked", Bool], // staked
  ["time", UInt], // network time
  ["secs", UInt], // network seconds
  ["delegateAddr", Address], // delegate address
]);

const State = Struct([
  ...Struct.fields(BaseState),
  ...Struct.fields(StakeState),
]);

// FUN

const fState = Fun([], State);
const fStake = Fun([Token, UInt], Null);
const fUnstake = Fun([], Null);
const fDeposit = Fun([UInt], Null);
const fWithdraw = Fun([UInt], Null);
const fGrant = Fun([Contract], Null);
const fClose = Fun([], Null);
const fDepositGrant = Fun([UInt, Contract], Null);
const fWithdrawGrant = Fun([UInt, Contract], Null);
const fUpdateDelegate = Fun([Address], Null);

// REMOTE FUN

export const rStake = (ctc, token, tokenAmount) => {
  const r = remote(ctc, { state: fState, stake: fStake });
  r.stake(token, tokenAmount);
  return r.state();
};

export const rUnstake = (ctc) => {
  const r = remote(ctc, { unstake: fUnstake });
  r.unstake();
};

// INTERACTS

const managerInteract = {
  getParams: Fun([], Params),
};

const relayInteract = {};

// CONTRACT

export const Event = () => [Events({ ...baseEvents })];

export const Participants = () => [
  Participant("Manager", managerInteract),
  Participant("Relay", relayInteract),
];

export const Views = () => [View(view(State))];

export const Api = () => [
  API({
    deposit: fDeposit,
    withdraw: fWithdraw,
    grant: fGrant,
    close: fClose,
    stake: fStake,
    unstake: fUnstake,
    depositGrant: fDepositGrant,
    withdrawGrant: fWithdrawGrant,
    updateDelegate: fUpdateDelegate,
  }),
];

export const App = (map) => {
  const [
    { amt, ttl, tok0: token },
    [addr, _],
    [Manager, Relay],
    [v],
    [a],
    [e],
  ] = map;

  Manager.only(() => {
    const { tokenAmount, remoteCtc } = declassify(interact.getParams());
  });

  // Step
  Manager.publish(tokenAmount, remoteCtc)
    .pay([amt + SERIAL_VER, [tokenAmount, token]])
    .timeout(relativeTime(ttl), () => {
      // Step
      Anybody.publish();
      commit();
      exit();
    });
  transfer([amt + SERIAL_VER]).to(addr);

  e.appLaunch();

  const initialState = {
    ...baseState(Manager),
    ...stakeState(Manager, token, tokenAmount, remoteCtc),
  };

  // Step
  const [s] = parallelReduce([initialState])
    .define(() => {
      v.state.set(State.fromObject(s));
    })
    // BALANCE
    .invariant(balance() == 0, "balance accurate")
    // TOKEN BALANCE
    .invariant(
      implies(!s.closed, balance(token) == s.tokenAmount),
      "token balance accurate before close"
    )
    .invariant(
      implies(s.closed, balance(token) == 0),
      "token balance accurate after close"
    )
    .while(!s.closed)
    .paySpec([token])
    // api: deposit
    //  allows manager to deposit more tokens
    .api_(a.deposit, (msg) => {
      check(this == s.manager, "only manager can deposit");
      check(!s.staked, "cannot deposit while staked");
      return [
        [0, [msg, token]],
        (k) => {
          k(null);
          return [
            {
              ...s,
              tokenAmount: s.tokenAmount + msg,
            },
          ];
        },
      ];
    })
    // api: withdraw
    //  allows manager to withdraw tokens
    .api_(a.withdraw, (msg) => {
      check(this == s.manager, "only manager can withdraw");
      check(!s.staked, "cannot withdraw while staked");
      check(msg <= s.tokenAmount, "cannot withdraw more than balance");
      return [
        (k) => {
          k(null);
          transfer(msg, token).to(this);
          return [
            {
              ...s,
              tokenAmount: s.tokenAmount - msg,
            },
          ];
        },
      ];
    })
    // api: grant
    //  allows manager to grant access to remote contract
    .api_(a.grant, (ctc) => {
      check(
        this == s.manager || this == s.delegateAddr,
        "only manager or delegate can grant"
      );
      check(!s.staked, "cannot grant while staked");
      return [
        (k) => {
          k(null);
          return [
            {
              ...s,
              remoteCtc: ctc,
            },
          ];
        },
      ];
    })
    // api: deposit grant
    //  allows manager to deposit more tokens and grant at the same time
    .api_(a.depositGrant, (msg, ctc) => {
      check(this == s.manager, "only manager can depositGrant");
      check(!s.staked, "cannot depositGrant while staked");
      return [
        [0, [msg, token]],
        (k) => {
          k(null);
          return [
            {
              ...s,
              tokenAmount: s.tokenAmount + msg,
              remoteCtc: ctc,
            },
          ];
        },
      ];
    })
    // api: withdraw grant
    //  allows manager to withdraw tokens and grant at the same time
    .api_(a.withdrawGrant, (msg, ctc) => {
      check(this == s.manager, "only manager can widrawGrant");
      check(!s.staked, "cannot withdrawGrant while staked");
      check(msg <= s.tokenAmount, "cannot withdraw more than balance");
      return [
        (k) => {
          k(null);
          transfer(msg, token).to(this);
          return [
            {
              ...s,
              tokenAmount: s.tokenAmount - msg,
              remoteCtc: ctc,
            },
          ];
        },
      ];
    })
    // api: update delegate
    //  allows manager to update delegate
    .api_(a.updateDelegate, (msg) => {
      check(this == s.manager, "only manager can update delegate");
      return [
        (k) => {
          k(null);
          return [
            {
              ...s,
              delegateAddr: msg,
            },
          ];
        },
      ];
    })
    // api: stake
    //  allows remote  contract to stake
    .api_(a.stake, (tok, tokAmt) => {
      check(
        Contract.addressEq(s.remoteCtc, this),
        "only remote contract can stake"
      );
      check(!s.staked, "cannot stake while staked");
      check(tok == token, "can only stake token");
      check(tokAmt < s.tokenAmount, "can only stake token amount");
      return [
        (k) => {
          k(null);
          return [
            {
              ...s,
              staked: true,
              time: thisConsensusTime(),
              secs: thisConsensusSecs(),
            },
          ];
        },
      ];
    })
    // api: unstake
    //  allows remote contract to unstake
    .api_(a.unstake, () => {
      check(
        Contract.addressEq(s.remoteCtc, this),
        "only remote contract can stake"
      );
      check(s.staked, "cannot unstake while not staked");
      return [
        (k) => {
          k(null);
          return [
            {
              ...s,
              staked: false,
              time: 0,
              secs: 0,
            },
          ];
        },
      ];
    })
    // api: close
    //  allows manager to close contract if not staked
    // . transferes staked amount to manger
    .api_(a.close, () => {
      check(this == s.manager, "only manager can close");
      check(!s.staked, "cannot close while staked");
      return [
        (k) => {
          k(null);
          transfer([[s.tokenAmount, token]]).to(s.manager);
          return [
            {
              ...s,
              closed: true,
              tokenAmount: 0,
            },
          ];
        },
      ];
    })
    .timeout(false);
  e.appClose();
  commit();
  Relay.publish();
  commit();
  exit();
};
// -----------------------------------------------
