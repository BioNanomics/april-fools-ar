#include "wpi/framework/TimedRobot.hpp"
#include "afsc_geometry.h"
#include <iostream>

// This wrapper is compiled by WPILib's C++23 toolchain; the core stays C++17.
class Robot final : public wpi::TimedRobot {
 public:
  Robot() {
    AFSCDistance distance{};
    if (afsc_distance({0, 0, 0}, {3, 4, 0}, &distance) == AFSC_GEOMETRY_OK) {
      std::cout << "AFSpatialCore distance: " << distance.distance_meters << " m\n";
    }
  }
};
int main() { return wpi::StartRobot<Robot>(); }
