"""Reference-test process settings. Never attach test runs to the desktop."""
import os


def headless_environment(frameworks=None):
    env = os.environ.copy()
    # SDL3 names plus SDL2 compatibility names. A missing dummy backend must fail
    # startup rather than fall back to Cocoa, create a window, or capture input.
    env.update(SDL_VIDEO_DRIVER="dummy", SDL_AUDIO_DRIVER="dummy",
               SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
    if frameworks:
        env["DYLD_FRAMEWORK_PATH"] = str(frameworks.resolve())
    return env


HEADLESS_OPTIONS = ["-noreadconfig", "-video", "none", "-sound", "none", "-window",
                    "-keyboardprovider", "none", "-mouseprovider", "none",
                    "-joystickprovider", "none", "-lightgunprovider", "none"]
