#ifndef RUNNER_WINDOWS_TOAST_CHANNEL_H_
#define RUNNER_WINDOWS_TOAST_CHANNEL_H_

#include <flutter/binary_messenger.h>

// Registers the `locus/windows_toasts` method channel.
void RegisterWindowsToastChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_WINDOWS_TOAST_CHANNEL_H_

