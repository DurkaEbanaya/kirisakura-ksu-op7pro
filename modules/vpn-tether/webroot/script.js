//
// VPN Tether - WebUI script.js
//

const MODDIR = "/data/adb/modules/vpn-tether";
const SCRIPTS = MODDIR + "/scripts";

// --- KSU shell exec helper ---
async function runShell(cmd) {
    if (typeof ksu === "undefined" || typeof ksu.exec !== "function") {
        throw new Error("KSU API unavailable");
    }
    return new Promise((res, rej) => {
        const cb = `cb_${Date.now()}_${Math.random()*10000|0}`;
        window[cb] = (code, stdout, stderr) => {
            delete window[cb];
            if (code === 0) {
                res((stdout || "").replace(/\r/g, ""));
            } else {
                rej(new Error(stderr || stdout || "Shell failed"));
            }
        };
        ksu.exec(cmd, "{}", cb);
    });
}

// --- Toast helper ---
function toast(msg) {
    try {
        if (typeof ksu !== "undefined" && ksu.toast) { ksu.toast(msg); return; }
        if (window.kernelsu && window.kernelsu.toast) { window.kernelsu.toast(msg); return; }
        if (window.toast) { window.toast(msg); return; }
    } catch {}
    console.log("[toast]", msg);
}

// --- JSON safe parse ---
function tryJSON(str) {
    try { return JSON.parse(str.trim()); } catch { return null; }
}

// --- State ---
let currentStatus = null;
let currentDevices = [];
let apStarting = false;

// --- Refresh status ---
async function refreshStatus() {
    try {
        const out = await runShell(`sh ${SCRIPTS}/status.sh`);
        const st = tryJSON(out);
        if (!st) return;

        currentStatus = st;
        renderBadges(st);
        renderAP(st);
        renderTether(st);
    } catch (e) {
        console.error("status error", e);
    }
}

// --- Refresh devices ---
async function refreshDevices() {
    try {
        const out = await runShell(`sh ${SCRIPTS}/list_devices.sh`);
        const devs = tryJSON(out);
        if (!devs) return;

        currentDevices = devs;
        renderDevices(devs);
    } catch (e) {
        console.error("devices error", e);
    }
}

// --- Render status badges ---
function renderBadges(st) {
    const el = document.getElementById("status-badges");
    let html = "";

    // WiFi
    if (st.wifi.connected) {
        html += `<span class="badge badge-on"><span class="badge-dot"></span>WiFi: ${st.wifi.ssid}</span>`;
    } else {
        html += `<span class="badge badge-off"><span class="badge-dot"></span>WiFi: OFF</span>`;
    }

    // VPN
    if (st.vpn.active) {
        html += `<span class="badge badge-on"><span class="badge-dot"></span>VPN: ${st.vpn.ip}</span>`;
    } else {
        html += `<span class="badge badge-off"><span class="badge-dot"></span>VPN: OFF</span>`;
    }

    // AP
    if (st.ap.active) {
        html += `<span class="badge badge-on"><span class="badge-dot"></span>AP: ${st.ap.clients} clients</span>`;
    }

    el.innerHTML = html;
}

// --- Render AP section ---
function renderAP(st) {
    const btn = document.getElementById("ap-toggle-btn");
    const controls = document.getElementById("ap-controls");
    const statusLine = document.getElementById("ap-status");

    if (st.ap.active) {
        btn.textContent = "Stop Hotspot";
        btn.className = "btn btn-danger";
        btn.disabled = false;
        controls.style.display = "none";
        statusLine.className = "status-line visible ok";
        statusLine.textContent = `Running: "${st.ap.ssid}" on ${st.ap.iface} (${st.ap.ip}) — ${st.ap.clients} client(s)`;
    } else {
        btn.textContent = "Start Hotspot";
        btn.className = "btn btn-primary";
        btn.disabled = false;
        controls.style.display = "";

        // Fill inputs from config
        if (st.ap_config) {
            document.getElementById("ap-ssid").value = st.ap_config.ssid || "";
            document.getElementById("ap-pass").value = st.ap_config.pass || "";
            document.getElementById("ap-channel").value = st.ap_config.channel || "6";
        }

        if (st.wifi.type === "ap") {
            statusLine.className = "status-line visible error";
            statusLine.textContent = "Android hotspot detected — framework fix in progress...";
        } else if (!st.wifi.connected) {
            statusLine.className = "status-line visible error";
            statusLine.textContent = "Connect to WiFi first";
        } else {
            statusLine.className = "status-line";
            statusLine.textContent = "";
        }
    }
}

// --- Render tether info ---
function renderTether(st) {
    const section = document.getElementById("tether-section");
    const info = document.getElementById("tether-info");
    let parts = [];

    if (st.tether.usb) parts.push('<span class="tether-badge">USB tethering active</span>');
    if (st.tether.bt) parts.push('<span class="tether-badge">Bluetooth tethering active</span>');

    if (parts.length > 0) {
        section.style.display = "";
        info.innerHTML = parts.join("");
    } else {
        section.style.display = "none";
    }
}

// --- Render devices list ---
function renderDevices(devs) {
    const el = document.getElementById("devices-list");

    if (!devs || devs.length === 0) {
        el.innerHTML = '<div class="empty-state">No devices connected</div>';
        return;
    }

    let html = "";
    for (const d of devs) {
        const vpnBtnClass = d.vpn ? "btn btn-vpn btn-vpn-on" : "btn btn-vpn btn-vpn-off";
        const vpnBtnText = d.vpn ? "VPN ON" : "Grant VPN";
        const typeLabel = {
            "wifi-ap": "WiFi",
            "usb": "USB",
            "bt": "BT"
        }[d.type] || d.type;

        html += `
            <div class="device-item">
                <div class="device-info">
                    <div class="device-ip">${d.ip}<span class="device-type type-${d.type}">${typeLabel}</span></div>
                    <div class="device-mac">${d.mac} · ${d.iface}</div>
                </div>
                <div class="device-vpn">
                    <button class="${vpnBtnClass}" onclick="toggleVPN('${d.ip}', ${d.vpn})">${vpnBtnText}</button>
                </div>
            </div>
        `;
    }

    el.innerHTML = html;
}

// --- Toggle AP ---
async function toggleAP() {
    if (apStarting) return;
    apStarting = true;

    const btn = document.getElementById("ap-toggle-btn");
    btn.disabled = true;

    try {
        if (currentStatus && currentStatus.ap.active) {
            // Stop
            btn.textContent = "Stopping...";
            const out = await runShell(`sh ${SCRIPTS}/stop_ap.sh`);
            const r = tryJSON(out);
            if (r && r.ok) {
                toast("Hotspot stopped");
            } else {
                toast("Error: " + (r ? r.error : "unknown"));
            }
        } else {
            // Start — save config first
            const ssid = document.getElementById("ap-ssid").value.trim();
            const pass = document.getElementById("ap-pass").value.trim();
            const channel = document.getElementById("ap-channel").value;

            if (!ssid) { toast("Enter SSID"); btn.disabled = false; apStarting = false; return; }
            if (pass.length < 8) { toast("Password must be 8+ chars"); btn.disabled = false; apStarting = false; return; }

            btn.textContent = "Saving...";

            // Save config only if changed
            const cfgOut = await runShell(`sh ${SCRIPTS}/update_config.sh "${ssid}" "${pass}" "${channel}"`);
            const cfgR = tryJSON(cfgOut);
            if (!cfgR || !cfgR.ok) {
                // Config might fail if AP is running — ignore and try to start
            }

            btn.textContent = "Starting...";

            const out = await runShell(`sh ${SCRIPTS}/start_ap.sh`);
            const r = tryJSON(out);
            if (r && r.ok) {
                toast(`Hotspot started: ${ssid}`);
            } else {
                toast("Error: " + (r ? r.error : "unknown"));
            }
        }
    } catch (e) {
        toast("Error: " + e.message);
    }

    apStarting = false;
    refreshStatus();
    refreshDevices();
}

// --- Toggle VPN for device ---
async function toggleVPN(ip, currentlyGranted) {
    try {
        if (currentlyGranted) {
            // Revoke
            const out = await runShell(`sh ${SCRIPTS}/revoke_vpn.sh "${ip}"`);
            const r = tryJSON(out);
            if (r && r.ok) {
                toast(`VPN revoked for ${ip}`);
            } else {
                toast("Error: " + (r ? r.error : "unknown"));
            }
        } else {
            // Grant
            if (currentStatus && !currentStatus.vpn.active) {
                toast("VPN is not active on this device");
                return;
            }

            const out = await runShell(`sh ${SCRIPTS}/grant_vpn.sh "${ip}"`);
            const r = tryJSON(out);
            if (r && r.ok) {
                toast(`VPN granted for ${ip}`);
            } else {
                toast("Error: " + (r ? r.error : "unknown"));
            }
        }
    } catch (e) {
        toast("Error: " + e.message);
    }

    refreshDevices();
}

// --- Init ---
async function init() {
    await refreshStatus();
    await refreshDevices();

    // Auto-refresh
    setInterval(refreshStatus, 3000);
    setInterval(refreshDevices, 3000);
}

// Full screen
try {
    if (window.kernelsu && window.kernelsu.fullScreen) window.kernelsu.fullScreen(true);
    else if (typeof ksu !== "undefined" && ksu.fullScreen) ksu.fullScreen(true);
    else if (window.fullScreen) window.fullScreen(true);
} catch {}

init();

// ─── Reveal Highlight: track mouse position for radial light effect ───
document.addEventListener("mousemove", function(e) {
    const targets = document.querySelectorAll(".btn, .device-item");
    for (const el of targets) {
        const rect = el.getBoundingClientRect();
        if (e.clientX >= rect.left && e.clientX <= rect.right &&
            e.clientY >= rect.top && e.clientY <= rect.bottom) {
            const x = ((e.clientX - rect.left) / rect.width) * 100;
            const y = ((e.clientY - rect.top) / rect.height) * 100;
            el.style.setProperty("--mouse-x", x + "%");
            el.style.setProperty("--mouse-y", y + "%");
        }
    }
}, { passive: true });
