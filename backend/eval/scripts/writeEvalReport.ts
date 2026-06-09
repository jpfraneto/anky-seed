#!/usr/bin/env bun
import { resolve } from "node:path";
import { latestRunDir, parseArgs, readRun, writeRunReport } from "./evalLib";

const args = parseArgs();
const runDir = typeof args["run-dir"] === "string" ? resolve(process.cwd(), args["run-dir"]) : await latestRunDir();

const run = await readRun(runDir);
const reportPath = await writeRunReport(run, runDir);
console.log(JSON.stringify({ status: "ok", reportPath }, null, 2));
