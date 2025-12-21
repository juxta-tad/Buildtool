#include <core/core.hpp>
#include <gtest/gtest.h>

TEST(CoreTest, VersionNotNull) {
  const char *v = core::version();
  ASSERT_NE(v, nullptr);
}

TEST(CoreTest, VersionFormat) {
  const char *v = core::version();
  EXPECT_STREQ("0.0.1", v);
}
