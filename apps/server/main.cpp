#include "raylib.h"
#include <cstdio>

int main() {
  InitWindow(800, 400, "Raylib + Buck2 + ?a");
  SetWindowFocused();
  Vector2 ballPosition = {400.0f, 300.0f};
  float ballRadius = 50.0f;
  Color ballColor = MAROON;
  SetTargetFPS(60);
  std::printf("hi\n");
  while (!WindowShouldClose()) {
    if (IsKeyDown(KEY_RIGHT))
      ballPosition.x += 4.0f;
    if (IsKeyDown(KEY_LEFT))
      ballPosition.x -= 4.0f;
    if (IsKeyDown(KEY_DOWN))
      ballPosition.y += 4.0f;
    if (IsKeyDown(KEY_UP))
      ballPosition.y -= 4.0f;

    BeginDrawing();
    ClearBackground(RAYWHITE);
    DrawCircleV(ballPosition, ballRadius, ballColor);
    DrawText("Arrow keys to move", 10, 10, 20, DARKGRAY);
    DrawFPS(10, 40);
    EndDrawing();
  }
  CloseWindow();
  return 0;
}
