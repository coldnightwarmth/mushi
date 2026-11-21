#pragma once
#include "NativeGame.h"
#include "Board.hpp"
// Tooling-only access for read-only asset observation and verification.
// The Swift frontend imports NativeGame.h, never this interface.
namespace futari { Board &inspectNativeGame(FutariGame game);Board &inspectNativeWorld(FutariGame game,unsigned world); }
