#!/bin/bash
# Fix all relative imports to absolute imports

set -e

echo "Fixing relative imports in Python files..."

# Fix all ..config imports
find src -name "*.py" -exec sed -i 's/from \.\.config import/from config import/g' {} \;

# Fix all ..netd imports
find src -name "*.py" -exec sed -i 's/from \.\.netd import/from netd import/g' {} \;

# Fix all ..kiosk imports
find src -name "*.py" -exec sed -i 's/from \.\.kiosk import/from kiosk import/g' {} \;

# Fix all ..portal imports
find src -name "*.py" -exec sed -i 's/from \.\.portal/from portal/g' {} \;

# Fix all ..api imports
find src -name "*.py" -exec sed -i 's/from \.\.api import/from api import/g' {} \;

echo "Relative imports fixed!"
echo "Changed:"
echo "  from ..config → from config"
echo "  from ..netd → from netd"
echo "  from ..kiosk → from kiosk"
echo "  from ..portal → from portal"
echo "  from ..api → from api"