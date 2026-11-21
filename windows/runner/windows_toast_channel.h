#ifndef RUNNER_WINDOWS_TOAST_CHANNEL_H_
#define RUNNER_WINDOWS_TOAST_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

// Supplies the top-level window handle for taskbar overlay updates.
void SetWindowsToastWindow(HWND window);

// Re-applies the last badge after Explorer restarts or the taskbar is created.
void ReapplyWindowsBadge();

// Registers the `locus/windows_toasts` method channel.
void RegisterWindowsToastChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_WINDOWS_TOAST_CHANNEL_H_

