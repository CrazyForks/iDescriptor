// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

#[cfg(target_os = "macos")]
mod ffi {
    unsafe extern "C" {
        pub fn setup_tool_frame(view_ptr: *mut std::ffi::c_void);
        pub fn setup_macos_main_window(view_ptr: *mut std::ffi::c_void);
    }
}

#[cfg(target_os = "macos")]
pub fn apply_tool_frame(win_id: usize) {
    if win_id == 0 {
        log::warn!("Skipping macOS tool window setup: QWindow::winId() returned 0");
        return;
    }

    log::debug!("Applying macOS tool window setup: {}", win_id);
    unsafe {
        ffi::setup_tool_frame(win_id as *mut std::ffi::c_void);
    }
}

#[cfg(not(target_os = "macos"))]
pub fn apply_tool_frame(_win_id: usize) {}

#[cfg(target_os = "macos")]
pub fn apply_main_window(win_id: usize) {
    if win_id == 0 {
        log::warn!("Skipping macOS main window setup: QWindow::winId() returned 0");
        return;
    }

    log::debug!("Applying macOS main window setup: {}", win_id);
    unsafe {
        ffi::setup_macos_main_window(win_id as *mut std::ffi::c_void);
    }
}

#[cfg(not(target_os = "macos"))]
pub fn apply_main_window(_win_id: usize) {}
