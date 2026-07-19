import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execa } from "execa";
import { glob } from "tinyglobby";
import { remote } from "webdriverio";
import {
	APPIUM_PORT,
	type AppiumServer,
	ensureAppiumDrivers,
	startAppiumServer,
} from "./appium.js";
import { ensureIosSimulator, type IosSimulator } from "./device.js";

export const ROOT = path.resolve(
	path.dirname(fileURLToPath(import.meta.url)),
	"..",
);
export const BUNDLE_ID = "dev.wvb.ios.testapp";
export const DEVICE_NAME = process.env.IOS_DEVICE ?? "iPhone 16";

export type Driver = Awaited<ReturnType<typeof remote>>;

export interface TestContext {
	server: AppiumServer;
	device: IosSimulator;
	driver: Driver;
}

/** Locates the built simulator `TestApp.app`. */
export async function findSimulatorApp(): Promise<string | undefined> {
	const fixed = path.join(
		ROOT,
		"TestApp",
		".build-xc",
		"Build",
		"Products",
		"Debug-iphonesimulator",
		"TestApp.app",
	);
	if (await pathExists(fixed)) {
		return fixed;
	}

	const pattern = path.join(
		os.homedir(),
		"Library/Developer/Xcode/DerivedData/TestApp-*/Build/Products/Debug-iphonesimulator/TestApp.app",
	);
	const matches = await glob(pattern, {
		onlyDirectories: true,
		absolute: true,
		expandDirectories: false,
	});
	if (matches.length === 0) {
		return undefined;
	}
	const withMtime = await Promise.all(
		matches.map(async (app) => ({ app, mtime: (await fs.stat(app)).mtimeMs })),
	);
	withMtime.sort((a, b) => b.mtime - a.mtime);
	// biome-ignore lint/style/noNonNullAssertion: expected
	return withMtime[0]!.app;
}

async function pathExists(p: string): Promise<boolean> {
	try {
		await fs.access(p);
		return true;
	} catch {
		return false;
	}
}

export async function createTestContext(): Promise<TestContext> {
	const appPath = await findSimulatorApp();
	if (!appPath) {
		throw new Error(
			"Built TestApp.app not found — the vitest globalSetup build step must run first.",
		);
	}

	await ensureAppiumDrivers(["xcuitest"]);
	const device = await ensureIosSimulator(DEVICE_NAME);

	console.log(
		`[device] installing ${path.basename(appPath)} -> ${device.udid}`,
	);
	// Uninstall first so each run starts from a clean app container (no leftover
	// downloaded/installed remote bundles), keeping the update flow deterministic.
	await execa("xcrun", ["simctl", "uninstall", device.udid, BUNDLE_ID]).catch(
		() => {},
	);
	await execa("xcrun", ["simctl", "install", device.udid, appPath]);

	const server = await startAppiumServer(APPIUM_PORT);

	const wdaTimeout = process.env.CI ? 600_000 : 300_000;
	const sessionTimeout = process.env.CI ? 720_000 : 360_000;

	// Launch by `appium:bundleId`; passing `appium:app` at a `.app` *directory*
	// trips the XCUITest driver with EISDIR.
	const driver = await remote({
		hostname: "127.0.0.1",
		port: server.port,
		path: "/",
		logLevel: "error",
		connectionRetryTimeout: sessionTimeout,
		connectionRetryCount: 0,
		capabilities: {
			platformName: "iOS",
			"appium:automationName": "XCUITest",
			"appium:udid": device.udid,
			"appium:deviceName": device.name,
			"appium:bundleId": BUNDLE_ID,
			"appium:newCommandTimeout": 240,
			"appium:wdaLaunchTimeout": wdaTimeout,
			"appium:wdaConnectionTimeout": wdaTimeout,
			"appium:webviewConnectTimeout": 30_000,
			// The WKWebView's inspectable page runs under a bundle id absent from
			// the driver's default match list, so without this no WEBVIEW context appears.
			"appium:additionalWebviewBundleIds": ["*"],
		},
	});

	await switchToWebview(driver);

	return { server, device, driver };
}

async function switchToWebview(driver: Driver): Promise<void> {
	for (let i = 0; i < 30; i++) {
		const contexts = (await driver.getContexts()) as Array<
			string | { id: string }
		>;
		const id = contexts
			.map((c) => (typeof c === "string" ? c : c.id))
			.find((c) => typeof c === "string" && c.startsWith("WEBVIEW"));
		if (id) {
			await driver.switchContext(id);
			return;
		}
		await new Promise((resolve) => setTimeout(resolve, 1000));
	}
	throw new Error(
		"WEBVIEW context never appeared (is Safari's Develop menu enabled?)",
	);
}

export async function disposeTestContext(
	context: TestContext | undefined,
): Promise<void> {
	if (!context) {
		return;
	}
	await context.driver.deleteSession().catch(() => {});
	await context.server.stop();
	if (context.device.bootedByUs && !process.env.WVB_E2E_KEEP) {
		await context.device.shutdown();
	}
}

let active: TestContext | undefined;

/** Set by `vitest.setup.ts`'s `beforeAll` so specs can reach the live context. */
export function setActiveContext(context: TestContext | undefined): void {
	active = context;
}

export function getTestContext(): TestContext {
	if (!active) {
		throw new Error(
			"Test context not started — vitest.setup.ts beforeAll did not run.",
		);
	}
	return active;
}
