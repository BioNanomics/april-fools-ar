#include "afsc_geometry.h"
#include <cmath>
#include <iostream>

int main() {
    AFSCDistance result{};
    if (afsc_distance({0, 0, 0}, {3, 4, 0}, &result) != AFSC_GEOMETRY_OK ||
        std::abs(result.distance_meters - 5) > 1e-12) return 1;
    std::cout << "AFSpatialCore " << afsc_version() << ": " << result.distance_meters << " m\n";
}
