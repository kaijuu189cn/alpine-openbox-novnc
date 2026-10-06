/*
 * webtop-adaptive.js -- make remote (adaptive) resize always effective.
 *
 * THE PROBLEM
 * -----------
 * The image patches noVNC's default to resize=remote, and Xvnc honours the
 * SetDesktopSize request, so the desktop follows the browser window. But
 * noVNC resolves the setting like this (app/ui.js, initSetting):
 *
 *     val = WebUtil.getConfigVar('resize');      // ?resize=... / #resize=...
 *     if (val === null) val = WebUtil.readSetting('resize', defVal);
 *                                             //  ^ localStorage wins here
 *
 * so a resize=off or resize=scale saved in the browser by an older image
 * silently beats the new default and the automatic resize never fires. There
 * is no way to fix that from the server side.
 *
 * WHAT THIS DOES
 * --------------
 * This module is loaded BEFORE vnc.html's inline module that calls UI.init(),
 * so it can still influence the resolution above: unless the URL says
 * otherwise, it stores resize=remote. The explicit URL parameter keeps
 * winning, which is the escape hatch:
 *
 *     ?resize=scale   scale locally, do not touch the server
 *     ?resize=off     no scaling, no resize (fixed desktop)
 *     ?resize=remote  the default, made to stick here
 *
 * It deliberately does NOT use noVNC's "mandatory" mechanism (mandatory.json):
 * that forces the value and grays out the settings control, which would take
 * the choice away from the user completely.
 *
 * Finally it records what it did on <html data-webtop-resize="..."> so
 * scripts/verify.sh can assert, in a real browser's DOM, that this ran.
 */
import * as WebUtil from './webutil.js';

const LOG_PREFIX = '[webtop-adaptive]';
const ATTRIBUTE = 'data-webtop-resize';

function apply() {
    let requested = null;
    try {
        requested = WebUtil.getConfigVar('resize');
    } catch (err) {
        console.warn(LOG_PREFIX, 'could not read the URL parameter:', err);
    }

    if (requested !== null) {
        console.log(LOG_PREFIX, 'URL asked for resize=' + requested + ', leaving it alone');
        return String(requested);
    }

    try {
        WebUtil.writeSetting('resize', 'remote');
        console.log(LOG_PREFIX, 'stored resize=remote (overrides any saved setting)');
        return 'remote';
    } catch (err) {
        // Storage can be unavailable (private mode, storage disabled). The
        // patched default is still resize=remote, so adaptive resize survives.
        console.warn(LOG_PREFIX, 'could not store the setting, relying on the default:', err);
        return 'default';
    }
}

const result = apply();

try {
    document.documentElement.setAttribute(ATTRIBUTE, result);
} catch (err) {
    console.warn(LOG_PREFIX, 'could not set ' + ATTRIBUTE + ':', err);
}
