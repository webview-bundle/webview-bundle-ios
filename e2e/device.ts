import { execa } from "execa";

export interface IosSimulator {
	udid: string;
	name: string;
	/** Whether this process booted the device (callers decide whether to shut it down). */
	bootedByUs: boolean;
	shutdown: () => Promise<void>;
}

interface SimDevice {
	udid: string;
	name: string;
	state: string;
}

async function listIosSimDevices(): Promise<SimDevice[]> {
	const { stdout } = await execa("xcrun", [
		"simctl",
		"list",
		"devices",
		"available",
		"--json",
	]);
	const parsed = JSON.parse(stdout) as {
		devices: Record<
			string,
			Array<{ udid: string; name: string; state: string }>
		>;
	};
	const out: SimDevice[] = [];
	for (const [runtime, devices] of Object.entries(parsed.devices)) {
		if (!/iOS/i.test(runtime)) {
			continue;
		}
		for (const d of devices) {
			out.push({ udid: d.udid, name: d.name, state: d.state });
		}
	}
	return out;
}

export async function ensureIosSimulator(
	deviceName: string,
): Promise<IosSimulator> {
	const devices = await listIosSimDevices();

	const booted = devices.find((d) => d.state === "Booted");
	if (booted != null) {
		return {
			udid: booted.udid,
			name: booted.name,
			bootedByUs: false,
			shutdown: async () => {},
		};
	}

	const target =
		devices.find((d) => d.name === deviceName) ??
		devices.find((d) => /^iPhone/i.test(d.name));
	if (target == null) {
		throw new Error(
			`No iOS simulator found (looked for "${deviceName}" or any iPhone).`,
		);
	}
	if (target.name !== deviceName) {
		console.log(
			`[device] "${deviceName}" not available; falling back to ${target.name}`,
		);
	}
	console.log(
		`[device] booting iOS simulator: ${target.name} (${target.udid})`,
	);
	await execa("xcrun", ["simctl", "boot", target.udid]);
	await execa("xcrun", ["simctl", "bootstatus", target.udid]); // blocks until fully booted
	return {
		udid: target.udid,
		name: target.name,
		bootedByUs: true,
		shutdown: async () => {
			await execa("xcrun", ["simctl", "shutdown", target.udid], {
				reject: false,
			});
		},
	};
}
