# Live OBS acceptance

Local build only. Login is not required. Use the existing OBS installation and macOS screen recording permission for OBS. Existing scenes and profiles are unchanged. Test in a new temporary scene before replacing the current capture setup.

1. Restart OBS when ready, add **macOS Capture with App Exclusions**, and select your display. Confirm the picture fills the source and text, colors and cursor look correct.
2. Put NotchPrompter over a moving window. Confirm it remains visible to you and is absent in both the OBS preview and a short recorded clip. Confirm content underneath it is visible, not covered by a black rectangle.
3. Add another app from the dropdown, close and reopen source properties, and confirm the exclusion persists. Remove it and confirm it becomes visible again.
4. Close and relaunch NotchPrompter during a test clip. Inspect the transition for any leaked frames. Also create a new window in an excluded app. Stop relying on the plugin for privacy if any transition leaks.
5. At OBS 60 FPS, record continuous scrolling or a known 60 FPS moving test for 60 seconds. Compare against native OBS display capture at the same resolution, canvas, scene, encoder and output settings, with only one capture source enabled per run. Inspect actual motion frames in the recording; the OBS output FPS counter alone does not prove 60 unique captured frames. Compare View → Stats rendering/encoding lag and Activity Monitor CPU/GPU load. No numeric performance threshold has been established by measurement yet.
6. Compare pointer/action responsiveness against native capture and Cloak. For latency measurements use a filmed input/display reference or a timestamped test pattern, rather than estimating solely from the preview.
7. Hide the source or switch scenes, then restore it. Confirm it resumes. Change exclusions while active and confirm a short blank transition instead of old unfiltered content.
8. Switch AeroSpace workspaces, unplug/reconnect a display, and sleep/wake. Confirm the chosen display resumes, or stays blank until Restart capture; it must not silently capture another display.

Reply with the check that failed, expected behavior and actual behavior. A passing build/module check is not approval to replace existing capture scenes, merge, publish or distribute this plugin.
