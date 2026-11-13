# Implementation ledger — resource-monitor 2026-11-10

User opted into direct completion. Working on codex/resource-monitor-redesign in the current checkout; preserving the existing Xcode user state modification. Baseline Debug build passed outside the agent sandbox. Existing app has no test target.

Ruling: Keep App Sandbox and report process access failures truthfully instead of relaxing security settings. Use deterministic standalone Swift regression tests for pure sampling math and process parsing, with real API/UI smoke checks for lifecycle and layouts.

Pre-flight: Task 1 SystemStats / ResourceLevel / MetricFormat feeds Tasks 2 and 3; one shared definition. Task 2 stable PID snapshots feed ProcessesView and compact process summary. AppDelegate controls visible sampling, sleep, and cadence.

RED: script/test.sh fails because MetricsMath.swift and ProcessSnapshot.swift do not yet exist, proving missing sampling and process parsing interfaces.

Tasks 1 and 2 implemented: interval CPU, per-interface network deltas, memory / swap / battery / thermal APIs, serial timers with generation guards, stable PID / RSS parsing, explicit process failure and persisted preferences. Pure suite passed 22 assertions. Integration smoke passed pause/resume, sleep/wake, history segmentation, and preference validation in the agent sandbox; process enumeration was denied as expected there.

UI smoke found MonitorCard ViewBuilder flattening content into separate grid cells; wrapped the content in a VStack. Verified via actual signed sandboxed app that process reads are denied. Asked user whether to enable an unsandboxed direct-distribution build; pending choice. CPU missing with known normal memory incorrectly showed healthy; reproduced with a failing regression and fixed. Pure suite now passes 23 assertions.

User explicitly approved disabling this app's App Sandbox for full system process monitoring. Ruling: change ENABLE_APP_SANDBOX to NO for Debug and Release; retain ENABLE_HARDENED_RUNTIME=YES. Updated spec / plan to reflect that choice. No system protection or administrator settings changed.

Independent review returned no Critical issues, one Important (getifaddrs counters are 32-bit), one Minor (nil metrics bridged by chart lines). Verified SDK declarations. Added 64-bit NET_RT_IFLIST2 decoder with bounds checks and retry; tests cover >4 GiB counters, truncation and zero message lengths. TrendSeries now splits each metric at missing values and source segments. Pure suite passes 30 assertions. All review issues addressed.

Actual UI verified: overview cards now correctly contain their charts, complete process enumeration (~850), name search, memory sort, pause/resume text, independent settings layout. Login startup left off; testing does not register a login item.

Final verification: Debug build/launch succeeded. Final Release build succeeded with local ad-hoc signing; codesign --verify --deep --strict passed. The only build warning is Xcode's skipped AppIntents metadata extraction (no AppIntents dependency). Final pure suite passed 30 assertions. Final integration passed with 844 live processes plus 64-bit routing API/rates, CPU/memory/disk/battery, pause/resume, sleep/wake, history segments and preferences.

Final UI: status popover now waits until menu tracking ends and becomes key, confirmed via accessibility and screenshot. Tested all display switches off (compact layout), then restored all switches on, alerts on, threshold 20%, balanced 2-second refresh, CPU status text. Login startup remains off. Settings open/close, process name search / memory sort and pause/resume verified. No dedicated forced-dark, minimum-window-size or real login/reboot test was performed; native semantic colors and minimum size constraints are implemented.

Delivery: README updated, Run action configured, scripts executable. Working changes kept uncommitted on codex/resource-monitor-redesign as specified; no merge or push. Existing user xcuserstate preserved. No remaining Critical/Important review issues.
