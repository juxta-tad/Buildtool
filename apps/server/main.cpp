#include "core/core.hpp"
#include <cstdio>

int main() {
  int x = 1;
  int y = 3;
  int z = x + y;

  std::printf("Core version: %s\n", core::version());
  std::printf("running the server... \n");
  std::printf("%d \n", z);
  return 0;
}
