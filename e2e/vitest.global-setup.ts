import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const TESTAPP = join(ROOT, "TestApp");

function run(cmd: string, args: string[], cwd: string): void {
	console.log(`\n$ ${cmd} ${args.join(" ")}  (cwd: ${cwd})`);
	const res = spawnSync(cmd, args, { cwd, stdio: "inherit" });
	if (res.status !== 0) {
		throw new Error(
			`command failed (${res.status ?? res.signal}): ${cmd} ${args.join(" ")}`,
		);
	}
}

export default function setup(): void {
	run("tuist", ["install"], TESTAPP);
	run("tuist", ["generate", "--no-open"], TESTAPP);
	run(
		"xcodebuild",
		[
			"build",
			"-workspace",
			"TestApp/TestApp.xcworkspace",
			"-scheme",
			"TestApp",
			"-destination",
			"generic/platform=iOS Simulator",
			"-derivedDataPath",
			"TestApp/.build-xc",
			"CODE_SIGNING_ALLOWED=NO",
		],
		ROOT,
	);
}
