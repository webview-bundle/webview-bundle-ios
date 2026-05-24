#!/usr/bin/env node

//
// install.mjs — Install the WebViewBundle FFI module published by the
// webview-bundle/webview-bundle repository into this Swift package.
//
// It fetches the GitHub release assets for a given tag and:
//   - extracts the Swift bindings from `apple.zip` into Sources/WebViewBundle/
//     (overwrite only — existing files that are not part of the asset are kept)
//   - resolves the SHA-256 checksum of `WebViewBundleFFI.xcframework.zip` (from
//     the digest GitHub reports for the asset, falling back to hashing the
//     archive) and writes both the checksum and the tag into Package.swift.
//
// Tags follow the upstream convention:
//   - release:    ffi/<version>      e.g. ffi/0.1.0
//   - prerelease: prerelease/<sha>   e.g. prerelease/a3f693a
//
// Usage:
//   node scripts/install.mjs 0.1.0                 # -> tag ffi/0.1.0
//   node scripts/install.mjs ffi/0.1.0             # explicit release tag
//   node scripts/install.mjs prerelease/a3f693a    # explicit prerelease tag
//   node scripts/install.mjs --prerelease a3f693a  # -> tag prerelease/a3f693a
//   node scripts/install.mjs latest                # highest ffi/* release
//
// Options:
//   --prerelease <sha>   Install the prerelease build for <sha> (tag prerelease/<sha>).
//   --repo <owner/repo>  Source repository (default: webview-bundle/webview-bundle).
//   -h, --help           Show this help.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	copyFileSync,
	existsSync,
	mkdirSync,
	mkdtempSync,
	readdirSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_DEFAULT = "webview-bundle/webview-bundle";
const APPLE_ASSET = "apple.zip";
const XCFRAMEWORK_ASSET = "WebViewBundleFFI.xcframework.zip";
const USER_AGENT = "webview-bundle-ios-install-ffi";

const ROOT_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const PACKAGE_SWIFT = join(ROOT_DIR, "Package.swift");
const SOURCES_DIR = join(ROOT_DIR, "Sources", "WebViewBundle");

// --- logging ----------------------------------------------------------------

const color = process.stdout.isTTY
	? {
			blue: "\x1b[34m",
			green: "\x1b[32m",
			yellow: "\x1b[33m",
			dim: "\x1b[2m",
			reset: "\x1b[0m",
		}
	: { blue: "", green: "", yellow: "", dim: "", reset: "" };

const log = (msg) => console.log(`${color.blue}==>${color.reset} ${msg}`);
const ok = (msg) => console.log(`${color.green} ✓ ${msg}${color.reset}`);
const warn = (msg) => console.error(`${color.yellow} ! ${msg}${color.reset}`);
const dim = (s) => `${color.dim}${s}${color.reset}`;

class CliError extends Error {}
const die = (msg) => {
	throw new CliError(msg);
};

// --- argument parsing --------------------------------------------------------

function printHelp() {
	const lines = readFileSync(fileURLToPath(import.meta.url), "utf8")
		.split("\n")
		.slice(1); // drop shebang
	const header = [];
	for (const line of lines) {
		if (!line.startsWith("//")) break; // stop at the first non-comment line
		header.push(line.replace(/^\/\/ ?/, ""));
	}
	console.log(header.join("\n"));
}

function parseArgs(argv) {
	let ref = "";
	let prerelease = "";
	let repo = REPO_DEFAULT;

	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i];
		if (arg === "-h" || arg === "--help") {
			printHelp();
			process.exit(0);
		} else if (arg === "--repo") {
			repo = argv[++i] ?? die("--repo requires a value");
		} else if (arg === "--prerelease") {
			prerelease = argv[++i] ?? die("--prerelease requires a sha");
		} else if (arg.startsWith("-")) {
			die(`unknown option: ${arg} (use --help)`);
		} else if (!ref) {
			ref = arg;
		} else {
			die(`unexpected extra argument: ${arg}`);
		}
	}
	return { ref, prerelease, repo };
}

// --- github ------------------------------------------------------------------

function ghHeaders(extra = {}) {
	const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
	return {
		Accept: "application/vnd.github+json",
		"User-Agent": USER_AGENT,
		"X-GitHub-Api-Version": "2022-11-28",
		...(token ? { Authorization: `Bearer ${token}` } : {}),
		...extra,
	};
}

// Honors GITHUB_API_URL (set by GitHub Actions; also enables GitHub Enterprise).
const API_BASE = (
	process.env.GITHUB_API_URL || "https://api.github.com"
).replace(/\/+$/, "");

async function githubJson(path) {
	const res = await fetch(`${API_BASE}/${path}`, { headers: ghHeaders() });
	if (!res.ok) {
		throw new Error(`GitHub API /${path} -> ${res.status} ${res.statusText}`);
	}
	return res.json();
}

// Compare two dotted versions numerically (e.g. "0.10.0" > "0.2.0").
function compareVersions(a, b) {
	const pa = a.split(".").map(Number);
	const pb = b.split(".").map(Number);
	for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
		const diff = (pa[i] || 0) - (pb[i] || 0);
		if (diff !== 0) return diff;
	}
	return 0;
}

async function resolveLatestFfiTag(repo) {
	const releases = await githubJson(`repos/${repo}/releases?per_page=100`);
	const versions = releases
		.map((r) => r.tag_name)
		.filter((t) => typeof t === "string" && t.startsWith("ffi/"))
		.map((t) => t.slice("ffi/".length))
		.sort(compareVersions);
	const latest = versions.at(-1);
	return latest ? `ffi/${latest}` : "";
}

async function resolveTag({ ref, prerelease, repo }) {
	if (prerelease) {
		if (ref) die("pass either a positional ref or --prerelease, not both");
		return `prerelease/${prerelease}`;
	}
	if (!ref) {
		die(
			"a version or tag is required (e.g. '0.1.0', 'ffi/0.1.0', 'latest'). See --help.",
		);
	}
	if (ref === "latest") {
		const tag = await resolveLatestFfiTag(repo);
		return tag || die(`no ffi/* release found in ${repo}`);
	}
	if (ref.includes("/")) return ref; // already a fully-qualified tag
	return `ffi/${ref}`; // bare version -> ffi/<version>
}

async function getRelease(repo, tag) {
	// The tag may contain a slash; this endpoint accepts it verbatim.
	try {
		return await githubJson(`repos/${repo}/releases/tags/${tag}`);
	} catch (err) {
		die(`release '${tag}' not found in ${repo} (${err.message})`);
	}
}

async function fetchAsset(release, name) {
	const asset = release.assets?.find((a) => a.name === name);
	if (!asset) die(`asset '${name}' not found in release '${release.tag_name}'`);
	// Use the asset API url with octet-stream so this also works for private
	// repos; fetch follows the redirect to the CDN and drops the auth header
	// on the cross-origin hop.
	const res = await fetch(asset.url, {
		headers: ghHeaders({ Accept: "application/octet-stream" }),
		redirect: "follow",
	});
	if (!res.ok)
		die(`failed to download '${name}': ${res.status} ${res.statusText}`);
	return Buffer.from(await res.arrayBuffer());
}

// Resolve the SHA-256 checksum of the xcframework archive. Prefer the digest
// GitHub reports in the asset metadata (no download needed); fall back to
// downloading the archive and hashing it when the digest is unavailable.
async function resolveXcframeworkChecksum(release) {
	const asset = release.assets?.find((a) => a.name === XCFRAMEWORK_ASSET);
	if (!asset)
		die(
			`asset '${XCFRAMEWORK_ASSET}' not found in release '${release.tag_name}'`,
		);

	const match =
		typeof asset.digest === "string"
			? asset.digest.match(/^sha256:([0-9a-f]{64})$/i)
			: null;
	if (match) {
		return { checksum: match[1].toLowerCase(), source: "GitHub digest" };
	}

	const buf = await fetchAsset(release, XCFRAMEWORK_ASSET);
	return {
		checksum: createHash("sha256").update(buf).digest("hex"),
		source: "computed",
	};
}

// --- install steps -----------------------------------------------------------

function updatePackageSwift(tag, checksum) {
	let src = readFileSync(PACKAGE_SWIFT, "utf8");
	// Replace the value regardless of current content, so this is idempotent
	// (works on the <PLACEHOLDER> and on previously-installed values alike).
	src = src.replace(/^let checksum = ".*"$/m, `let checksum = "${checksum}"`);
	src = src.replace(/^let tag = ".*"$/m, `let tag = "${tag}"`);
	if (!src.includes(`let checksum = "${checksum}"`))
		die("failed to write checksum into Package.swift");
	if (!src.includes(`let tag = "${tag}"`))
		die("failed to write tag into Package.swift");
	writeFileSync(PACKAGE_SWIFT, src);
}

function walkFiles(dir) {
	const out = [];
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, entry.name);
		if (entry.isDirectory()) out.push(...walkFiles(full));
		else if (entry.isFile()) out.push(full);
	}
	return out;
}

// Locate the `src/` directory inside the extracted apple.zip (shallowest match).
function findSrcDir(root) {
	const queue = [root];
	while (queue.length > 0) {
		const dir = queue.shift();
		const subdirs = [];
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			if (!entry.isDirectory()) continue;
			if (entry.name === "src") return join(dir, entry.name);
			subdirs.push(join(dir, entry.name));
		}
		queue.push(...subdirs);
	}
	return null;
}

function installSwiftSources(appleZipPath, tmpDir) {
	const extractDir = join(tmpDir, "apple");
	mkdirSync(extractDir, { recursive: true });
	try {
		execFileSync("unzip", ["-q", "-o", appleZipPath, "-d", extractDir]);
	} catch (err) {
		if (err.code === "ENOENT")
			die("'unzip' is required but was not found on PATH");
		die(`failed to unzip ${APPLE_ASSET}: ${err.message}`);
	}

	// The Swift bindings live under a `src/` directory inside apple.zip
	// (e.g. src/WebViewBundleLibrary.swift). Copy that directory's Swift files
	// into Sources/WebViewBundle/, preserving any sub-paths under src/, so that
	// src/WebViewBundleLibrary.swift -> Sources/WebViewBundle/WebViewBundleLibrary.swift.
	const srcDir = findSrcDir(extractDir);
	if (!srcDir) die(`no 'src/' directory found inside ${APPLE_ASSET}`);

	const swiftFiles = walkFiles(srcDir).filter(
		(f) => f.endsWith(".swift") && basename(f) !== "Package.swift",
	);
	if (swiftFiles.length === 0)
		die(`no .swift files found under 'src/' in ${APPLE_ASSET}`);

	mkdirSync(SOURCES_DIR, { recursive: true });
	const installed = [];
	for (const file of swiftFiles) {
		const rel = relative(srcDir, file); // path under src/
		const dest = join(SOURCES_DIR, rel);
		mkdirSync(dirname(dest), { recursive: true });
		copyFileSync(file, dest); // overwrite only; other files untouched
		installed.push(rel);
	}
	return installed;
}

function validateManifest() {
	try {
		execFileSync(
			"swift",
			["package", "--package-path", ROOT_DIR, "dump-package"],
			{
				stdio: "ignore",
			},
		);
		ok("Package.swift manifest is valid");
	} catch (err) {
		if (err.code === "ENOENT") return; // swift not installed — skip the optional check
		warn(
			"Package.swift was updated but 'swift package dump-package' failed — please review it.",
		);
	}
}

// --- main --------------------------------------------------------------------

async function main() {
	const args = parseArgs(process.argv.slice(2));
	const tag = await resolveTag(args);

	if (!existsSync(PACKAGE_SWIFT))
		die(`Package.swift not found at ${PACKAGE_SWIFT}`);

	log(`Source repo : ${dim(args.repo)}`);
	log(`Release tag  : ${dim(tag)}`);

	const release = await getRelease(args.repo, tag);

	// Resolve the checksum and download apple.zip up front, so Package.swift /
	// Sources are only mutated once we know the release and its assets exist.
	log("Fetching release…");
	const { checksum, source } = await resolveXcframeworkChecksum(release);
	const appleZip = await fetchAsset(release, APPLE_ASSET);
	log(`Checksum     : ${dim(checksum)} ${dim(`(${source})`)}`);
	ok(`Downloaded ${APPLE_ASSET}`);

	const tmpDir = mkdtempSync(join(tmpdir(), "install-ffi-"));
	try {
		// 1) Update Package.swift with the tag + checksum.
		updatePackageSwift(tag, checksum);
		ok("Updated Package.swift (tag + checksum)");

		// 2) Extract the Swift bindings into Sources/WebViewBundle/.
		const appleZipPath = join(tmpDir, APPLE_ASSET);
		writeFileSync(appleZipPath, appleZip);
		log(
			`Installing Swift sources into ${dim(`${relative(ROOT_DIR, SOURCES_DIR)}/`)}`,
		);
		const installed = installSwiftSources(appleZipPath, tmpDir);
		for (const name of installed) console.log(`   - ${name}`);
		ok(`Installed ${installed.length} Swift file(s)`);

		// 3) Sanity check the manifest still parses.
		validateManifest();
	} finally {
		rmSync(tmpDir, { recursive: true, force: true });
	}

	log(`Done. Installed FFI module ${color.green}${tag}${color.reset}.`);
}

main().catch((err) => {
	if (err instanceof CliError) {
		console.error(`error: ${err.message}`);
	} else {
		console.error(`error: ${err.message ?? err}`);
	}
	process.exit(1);
});
