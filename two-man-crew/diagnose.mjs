// Reads the newest Project Zomboid log and reports what TwoManCrew actually
// did, in plain language.
//
// It exists because three "fixed" builds in a row were shipped on reasoning
// rather than evidence. The mod now prints at three points - when a server
// file loads, when the client sends a request, and when the server receives
// one - and this turns those prints into a verdict about WHERE the chain
// breaks, instead of another guess.
//
// Run: npm run diagnose

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const LOGS = join(homedir(), "Zomboid", "Logs");

function newestLog() {
  const files = readdirSync(LOGS)
    .filter((f) => f.endsWith("DebugLog.txt"))
    .map((f) => ({ f, t: statSync(join(LOGS, f)).mtimeMs }))
    .sort((a, b) => b.t - a.t);
  if (files.length === 0) throw new Error(`no DebugLog files in ${LOGS}`);
  return files[0];
}

const { f, t } = newestLog();
const text = readFileSync(join(LOGS, f), "utf8");
const lines = text.split("\n");

const mine = lines.filter((l) => l.includes("TwoManCrew["));
const loadedMod = lines.some((l) => /loading TwoManCrew/i.test(l));

// Any Lua error mentioning the mod, or a stack frame from one of its files.
const errors = lines.filter(
  (l) => /TwoManCrew/i.test(l) && /ERROR|Exception|attempt to/i.test(l),
);

console.log(`log:  ${f}`);
console.log(`when: ${new Date(t).toLocaleString()}`);
console.log(`mod loaded by the game: ${loadedMod ? "yes" : "NO"}`);
console.log("");

if (mine.length === 0) {
  console.log("No TwoManCrew diagnostic output at all.");
  console.log("");
  console.log("That means either this log predates the 0.2.2 install, or the");
  console.log("mod's Lua never ran. Start the game, load a save, press the");
  console.log("refresh and claim buttons, quit, then run this again.");
} else {
  const say = (label, re) => {
    const hit = mine.filter((l) => re.test(l));
    console.log(
      `${hit.length ? "yes" : "NO "}  ${label}${hit.length > 1 ? `  (x${hit.length})` : ""}`,
    );
    return hit.length > 0;
  };

  console.log("Chain, in order - the first NO is where it breaks:");
  const campaignLoaded = say(
    "server claim handler registered",
    /Campaign\.lua LOADED/,
  );
  const reportLoaded = say(
    "server refresh handler registered",
    /CrewReport\.lua LOADED/,
  );
  const sentClaim = say("client sent a claim request", /sending requestClaim/);
  const sentReport = say(
    "client sent a refresh request",
    /sending requestCrewReport/,
  );
  const gotAny = say(
    "server received any command",
    /got command|CrewReport got/,
  );
  const replied = say("client received a reply", /server replied/);

  console.log("");
  const guard = mine.find((l) => /reached guard/.test(l));
  if (guard)
    console.log(`guard values: ${guard.slice(guard.indexOf("isClient="))}`);

  console.log("");
  if (!campaignLoaded || !reportLoaded) {
    console.log("VERDICT: the server-side files never ran, so nothing can");
    console.log("answer a button. The guard values above say why.");
  } else if (!sentClaim && !sentReport) {
    console.log("VERDICT: the buttons never sent anything - the fault is in");
    console.log("the click handling, not the server.");
  } else if (!gotAny) {
    console.log("VERDICT: the client sends and the server never receives.");
    console.log("The command never crosses in singleplayer.");
  } else if (!replied) {
    console.log("VERDICT: the server receives but its reply never arrives.");
    console.log("Look for an error between receiving and replying.");
  } else {
    console.log("VERDICT: the full round trip completed. If a button still");
    console.log("looks dead, the fault is in what is drawn, not the data.");
  }
}

if (errors.length) {
  console.log("");
  console.log("Errors mentioning the mod:");
  for (const e of errors.slice(0, 10))
    console.log("  " + e.trim().slice(0, 160));
}

// Probe output, added 2026-08-23. TwoManCrew_Probe.lua prints one
// "TwoManCrew[probe] fact = value" line per read. This groups them by fact and
// shows the LAST value seen, because later passes happen with the crew in
// different places and the last one is the most recent state of the world.
const probeLines = lines.filter((l) => l.includes("TwoManCrew[probe]"));

console.log("");
if (probeLines.length === 0) {
  console.log("No probe output in this log.");
  console.log("");
  console.log("Either this log predates the probe build, or the probe never");
  console.log(
    "ran. It fires on the game's ten-minute tick, so load a save and",
  );
  console.log("let roughly an in-game hour pass, then run this again.");
} else {
  const facts = new Map();
  for (const line of probeLines) {
    const match = line.match(/TwoManCrew\[probe\] (.+?) = (.*)$/);
    if (!match) continue;
    const [, fact, value] = match;
    if (!facts.has(fact)) facts.set(fact, []);
    facts.get(fact).push(value.trim());
  }

  console.log(`Probe facts (${probeLines.length} lines):`);
  for (const [fact, values] of facts) {
    const last = values[values.length - 1];
    const varied =
      new Set(values).size > 1
        ? `  (varied across ${values.length} passes)`
        : "";
    console.log(`  ${fact} = ${last}${varied}`);
  }
}
