"""customtkinter dashboard for PhoneHub.

A scrollable grid of device tiles (model / OS / platform / short serial /
status) with a global Refresh button (re-runs discovery) and per-tile Focus and
Screenshot buttons.

Threading model: blocking work (discovery, scrcpy launch, screenshot capture)
runs on a background ``threading.Thread`` so the Tk event loop never freezes.
Results are marshalled back onto the UI thread with ``widget.after(...)``,
which is the supported way to touch Tk widgets from another thread.
"""

from __future__ import annotations

import threading
from typing import Callable, List, Optional

import customtkinter as ctk

from .devices import Device
from .discovery import discover
from .focus import focus
from .screenshot import capture

_GRID_COLUMNS = 2


class DeviceTile(ctk.CTkFrame):
    """A single device card with Focus + Screenshot actions."""

    def __init__(
        self,
        master: ctk.CTkBaseClass,
        device: Device,
        on_focus: Callable[[Device], None],
        on_screenshot: Callable[[Device], None],
    ) -> None:
        super().__init__(master, corner_radius=10, border_width=1)
        self.device = device

        platform_label = "iOS" if device.platform == "ios" else "Android"
        header = ctk.CTkLabel(
            self,
            text=f"{device.model}",
            font=ctk.CTkFont(size=15, weight="bold"),
            anchor="w",
        )
        header.grid(row=0, column=0, columnspan=2, sticky="ew", padx=12, pady=(10, 0))

        meta = (
            f"{platform_label}  ·  {device.os_version}\n"
            f"{device.short_id}  ·  {device.status}"
        )
        body = ctk.CTkLabel(self, text=meta, justify="left", anchor="w")
        body.grid(row=1, column=0, columnspan=2, sticky="ew", padx=12, pady=(2, 8))

        focus_btn = ctk.CTkButton(
            self, text="Focus", width=110,
            command=lambda: on_focus(self.device),
        )
        focus_btn.grid(row=2, column=0, padx=(12, 6), pady=(0, 12), sticky="ew")

        shot_btn = ctk.CTkButton(
            self, text="Screenshot", width=110, fg_color="gray30",
            command=lambda: on_screenshot(self.device),
        )
        shot_btn.grid(row=2, column=1, padx=(6, 12), pady=(0, 12), sticky="ew")

        self.grid_columnconfigure((0, 1), weight=1)


class Dashboard(ctk.CTk):
    """Top-level PhoneHub window."""

    def __init__(self) -> None:
        super().__init__()
        self.title("PhoneHub — Device Dashboard")
        self.geometry("720x560")
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(2, weight=1)

        title = ctk.CTkLabel(
            self, text="PhoneHub", font=ctk.CTkFont(size=22, weight="bold")
        )
        title.grid(row=0, column=0, sticky="w", padx=20, pady=(16, 0))

        toolbar = ctk.CTkFrame(self, fg_color="transparent")
        toolbar.grid(row=1, column=0, sticky="ew", padx=16, pady=(6, 8))
        toolbar.grid_columnconfigure(0, weight=1)

        self.status_var = ctk.StringVar(value="Ready.")
        self.status_label = ctk.CTkLabel(
            toolbar, textvariable=self.status_var, anchor="w"
        )
        self.status_label.grid(row=0, column=0, sticky="ew", padx=(4, 8))

        self.refresh_btn = ctk.CTkButton(
            toolbar, text="Refresh", width=120, command=self.refresh
        )
        self.refresh_btn.grid(row=0, column=1, sticky="e")

        self.grid_area = ctk.CTkScrollableFrame(self, label_text="Connected devices")
        self.grid_area.grid(row=2, column=0, sticky="nsew", padx=16, pady=(0, 16))
        for col in range(_GRID_COLUMNS):
            self.grid_area.grid_columnconfigure(col, weight=1)

        self._tiles: List[DeviceTile] = []
        self.refresh()

    # ----- status helpers (always called on the UI thread) ----------------- #

    def _set_status(self, text: str) -> None:
        self.status_var.set(text)

    # ----- discovery / refresh --------------------------------------------- #

    def refresh(self) -> None:
        """Re-run discovery on a background thread, then rebuild the grid."""
        self.refresh_btn.configure(state="disabled")
        self._set_status("Discovering devices…")
        self._run_async(discover, self._on_devices)

    def _on_devices(self, devices: List[Device]) -> None:
        for tile in self._tiles:
            tile.destroy()
        self._tiles = []

        if not devices:
            empty = ctk.CTkLabel(
                self.grid_area,
                text=(
                    "No devices found.\n"
                    "Connect an iPhone (libimobiledevice) or Android device "
                    "(adb), then press Refresh."
                ),
                justify="center",
            )
            empty.grid(row=0, column=0, columnspan=_GRID_COLUMNS, pady=40)
            self._tiles.append(empty)  # type: ignore[arg-type]
        else:
            for index, device in enumerate(devices):
                tile = DeviceTile(
                    self.grid_area,
                    device,
                    on_focus=self._on_focus_click,
                    on_screenshot=self._on_screenshot_click,
                )
                row, col = divmod(index, _GRID_COLUMNS)
                tile.grid(row=row, column=col, padx=8, pady=8, sticky="nsew")
                self._tiles.append(tile)

        self.refresh_btn.configure(state="normal")
        self._set_status(f"Found {len(devices)} device(s).")

    # ----- per-tile actions ------------------------------------------------ #

    def _on_focus_click(self, device: Device) -> None:
        self._set_status(f"Focusing {device.short_id}…")
        self._run_async(
            lambda: focus(device),
            lambda result: self._set_status(result.message),
        )

    def _on_screenshot_click(self, device: Device) -> None:
        self._set_status(f"Capturing screenshot of {device.short_id}…")
        self._run_async(
            lambda: capture(device),
            lambda result: self._set_status(result.message),
        )

    # ----- threading bridge ------------------------------------------------ #

    def _run_async(
        self,
        work: Callable[[], object],
        done: Callable[[object], None],
    ) -> None:
        """Run ``work()`` off the UI thread; deliver its result to ``done`` on it."""

        def runner() -> None:
            try:
                result: object = work()
                error: Optional[BaseException] = None
            except BaseException as exc:  # never let a worker thread die silently
                result, error = None, exc
            # Hop back to the Tk thread.
            self.after(0, lambda: self._deliver(done, result, error))

        threading.Thread(target=runner, daemon=True).start()

    def _deliver(
        self,
        done: Callable[[object], None],
        result: object,
        error: Optional[BaseException],
    ) -> None:
        if error is not None:
            self.refresh_btn.configure(state="normal")
            self._set_status(f"Error: {error}")
            return
        done(result)


def run() -> None:
    """Launch the dashboard."""
    ctk.set_appearance_mode("system")
    ctk.set_default_color_theme("blue")
    app = Dashboard()
    app.mainloop()
