"reach 0.1";
"use strict";

// -----------------------------------------------
// Name: KINN Stake Contract
// Version: 0.1.4 - protect relay from rt
// Requires Reach v0.1.11-rc7 (27cb9643) or later
// -----------------------------------------------

// CONSTS

const SERIAL_VER = 0;

const FEE_MIN_RELAY = 6_000; 

// TYPES

const Params = Object({
  tokenAmount: UInt, // NFT token amount
  remoteCtc: Contract, // remote contract
  relayFee: UInt, // relay fee
});

const State = Struct([
  ["manager", Address], // manager address
  ["token", Token], // NFT token
  ["tokenAmount", UInt], // NFT token amount
  ["remoteCtc", Contract], // remote contract
  ["staked", Bool], // staked
  ["closed", Bool], // closed
  ["time", UInt], // network time
  ["secs", UInt], // network seconds
]);

// FUN

const state = Fun([], State);
const stake = Fun([Token, UInt], Null);
const unstake = Fun([], Null);

// REMOTE FUN

export const rStake = (ctc, token, tokenAmount) => {
  const r = remote(ctc, { state, stake });
  r.stake(token, tokenAmount);
  return r.state();
};

export const rUnstake = (ctc) => {
  const r = remote(ctc, { unstake });
  r.unstake();
};

// INTERACTS

const managerInteract = {
  getParams: Fun([], Params),
  signal: Fun([], Null),
};

const relayInteract = {};

// CONTRACT

export const Event = () => [];

export const Participants = () => [
  Participant("Manager", managerInteract),
  Participant("Relay", relayInteract),
];

export const Views = () => [
  View({
    state: State,
  }),
];

export const Api = () => [
  API({
    deposit: Fun([UInt], Null),
    withdraw: Fun([UInt], Null),
    grant: Fun([Contract], Null),
    close: Fun([], Null),
    stake,
    unstake,
  }),
];

export const App = (map) => {
  const [{ amt, ttl, tok0: token }, [addr, _], [Manager, Relay], [v], [a], _] =
    map;

  Manager.only(() => {
    const { tokenAmount, remoteCtc, relayFee } = declassify(
      interact.getParams()
    );
  });

  // Step
  Manager.publish(tokenAmount, remoteCtc, relayFee)
    .check(() => {
      check(relayFee >= FEE_MIN_RELAY, "relay fee too low");
    })
    .pay([amt + SERIAL_VER + relayFee, [tokenAmount, token]])
    .timeout(relativeTime(ttl), () => {
      // Step
      Anybody.publish();
      commit();
      exit();
    });
  transfer([amt + SERIAL_VER]).to(addr);

  Manager.interact.signal();

  const initialState = {
    manager: Manager,
    staked: false,
    closed: false,
    token,
    tokenAmount,
    remoteCtc,
    time: 0,
    secs: 0,
  };

  // Step
  const [s] = parallelReduce([initialState])
    .define(() => {
      v.state.set(State.fromObject(s));
    })
    // BALANCE
    .invariant(balance() == relayFee, "balance accurate")
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
      check(this == s.manager, "only manager can deposit");
      check(!s.staked, "cannot deposit while staked");
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
      check(this == s.manager, "only manager can close");
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
  commit();
  Relay.publish();
  const rt = getUntrackedFunds(token);
  transfer([relayFee, [rt, token]]).to(Relay);
  commit();
  exit();
};
// -----------------------------------------------
