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
