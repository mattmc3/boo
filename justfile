# Boo build tasks. Needs the .NET 10 SDK and nothing else.
#
# The test suite verifies every assembly it generates with ilverify. Without it
# the tests still run, they just skip verification:
#
#     dotnet tool install --global dotnet-ilverify

# Build the compiler, the Boo libraries and the tests.
build:
    dotnet build Boo.slnx

# Run the tests.
test:
    dotnet test Boo.slnx

# Delete the build output, including the obj directories dotnet clean keeps.
# The two stage bootstrap means a stale booc can compile the Boo projects
# against yesterday's libraries, and this is how you rule that out.
clean:
    dotnet clean Boo.slnx
    find src tests -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} +

# Apply the formatting and code style in .editorconfig.
format:
    dotnet format Boo.slnx

# Report what formatting would change, without touching anything.
format-check:
    dotnet format Boo.slnx --verify-no-changes
