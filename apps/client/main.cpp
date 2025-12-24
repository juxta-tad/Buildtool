#include "core/core.hpp"

#include <cstdio>
#include <raylib.h>

int main() {

  std::printf("Core version: %s\n", core::version());

  InitWindow(800, 600, "Rotating Cube");
  SetWindowFocused();

  Camera3D camera = {};

  camera.fovy = 45.0F;
  camera.target = {0.0f, 0.0F, 0.0f};
  camera.position = {5.0f, 5.0f, 5.0f};
  camera.up = {0.0F, 1.0f, 0.0f};
  camera.projection = CAMERA_PERSPECTIVE;

  Model cube = LoadModelFromMesh(GenMeshCube(2.0f, 2.0f, 2.0f));
  float rotation = 0.0f;

  SetTargetFPS(60);

  while (!WindowShouldClose()) {
    rotation += 1.0f;
    BeginDrawing();
    ClearBackground(BLACK);
    BeginMode3D(camera);

    DrawModelEx(cube, {0.0f, 0.0f, 0.0f}, {1.0f, 1.0f, 0.0f}, rotation,
                {1.0f, 1.0f, 1.0f}, MAROON);

    EndMode3D();

    DrawFPS(10, 10);
    EndDrawing();
  }

  UnloadModel(cube);
  CloseWindow();
  return 0;
}
