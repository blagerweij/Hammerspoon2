//
//  hs.audiodevice.js
//  Hammerspoon 2
//

"use strict";

// Lazily starts the underlying CoreAudio listener on the first listener (for any event) and
// stops it once the last listener (across all events) is removed. See Engine/engine.js for
// LazyWatcherEmitter itself.
hs.audiodevice._watcherEmitter = new LazyWatcherEmitter("hs.audiodevice", function() {
    return hs.audiodevice._addWatcher((event, ...args) => {
        hs.audiodevice._watcherEmitter.emit(event, ...args);
    });
}, function() {
    hs.audiodevice._removeWatcher();
}, hs.audiodevice._eventNames);

/// Register a listener for a named system-level audio configuration event.
/// Parameters:
///  - event: {"dOut" | "dIn" | "dSErr" | "dev+" | "dev-"} The event to listen for
///  - listener: {(device: HSAudioDevice | {id: number, uid: string, name: string} | null) => void} Called when the event occurs. For `"dOut"`, `"dIn"` and `"dSErr"` it is passed the new default device (or `null` if there is none), for `"dev+"` the device that was added, and for `"dev-"` an `{id, uid, name}` object describing the device that was removed (it can no longer be used)
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.audiodevice.on('dOut', (device) => console.log("Default output is now " + (device ? device.name : "none")))
///     hs.audiodevice.on('dev+', (device) => console.log("Added " + device.name))
///     hs.audiodevice.on('dev-', (removed) => console.log("Removed " + removed.name))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.audiodevice.on = function(event, listener) {
    hs.audiodevice._watcherEmitter.on(event, listener);
};

/// Remove a previously registered system-level audio event listener.
/// Parameters:
///  - event: {"dOut" | "dIn" | "dSErr" | "dev+" | "dev-"} The event the listener was registered for
///  - listener: {(device: HSAudioDevice | {id: number, uid: string, name: string} | null) => void} The function originally passed to `on`
/// Example:
/// ```js
/// const onDefaultOutChange = () => console.log("changed")
/// hs.audiodevice.on('dOut', onDefaultOutChange)
/// // later…
/// hs.audiodevice.off('dOut', onDefaultOutChange)
/// ```
hs.audiodevice.off = function(event, listener) {
    hs.audiodevice._watcherEmitter.off(event, listener);
};

/// Register a listener that fires at most once for a system-level audio configuration event.
/// Parameters:
///  - event: {"dOut" | "dIn" | "dSErr" | "dev+" | "dev-"} The event to listen for
///  - listener: {(device: HSAudioDevice | {id: number, uid: string, name: string} | null) => void} Called the next time a matching event occurs, then automatically removed. Passed the same value as for `on()`
/// Throws: true
/// Example:
/// ```js
/// try {
///     hs.audiodevice.once('dev+', (device) => console.log("First device added: " + device.name))
/// } catch (err) {
///     console.error(err.message)
/// }
/// ```
hs.audiodevice.once = function(event, listener) {
    hs.audiodevice._watcherEmitter.once(event, listener);
};

// Factory for per-device emitters; called lazily from Swift when the first on()/once() call is
// made on a device. `device` is the HSAudioDevice instance; its own on/off/once methods (native
// Swift, not JS-assigned - a per-instance object has no enhancement script to hang them on)
// forward into this emitter.
/// SKIP_DOCS
hs.audiodevice._makeDeviceEmitter = function(device) {
    return new LazyWatcherEmitter("hs.audiodevice device", function() {
        return device._addWatcher((event, ...args) => {
            device._watcherEmitter.emit(event, ...args);
        });
    }, function() {
        device._removeWatcher();
    }, device._eventNames);
};
