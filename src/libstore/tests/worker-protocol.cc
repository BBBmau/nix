#include <regex>

#include <nlohmann/json.hpp>
#include <gtest/gtest.h>

#include "worker-protocol.hh"
#include "worker-protocol-impl.hh"
#include "derived-path.hh"
#include "build-result.hh"
#include "tests/libstore.hh"

namespace nix {

class WorkerProtoTest : public LibStoreTest
{
public:
    Path unitTestData = getEnv("_NIX_TEST_UNIT_DATA").value() + "/libstore/worker-protocol";

    bool testAccept() {
        return getEnv("_NIX_TEST_ACCEPT") == "1";
    }

    Path goldenMaster(std::string_view testStem) {
        return unitTestData + "/" + testStem + ".bin";
    }

    /**
     * Golden test for `T` reading
     */
    template<typename T>
    void readTest(PathView testStem, T value)
    {
        if (testAccept())
        {
            GTEST_SKIP() << "Cannot read golden master because another test is also updating it";
        }
        else
        {
            auto expected = readFile(goldenMaster(testStem));

            T got = ({
                StringSource from { expected };
                WorkerProto::Serialise<T>::read(
                    *store,
                    WorkerProto::ReadConn { .from = from });
            });

            ASSERT_EQ(got, value);
        }
    }

    /**
     * Golden test for `T` write
     */
    template<typename T>
    void writeTest(PathView testStem, const T & value)
    {
        auto file = goldenMaster(testStem);

        StringSink to;
        WorkerProto::write(
            *store,
            WorkerProto::WriteConn { .to = to },
            value);

        if (testAccept())
        {
            createDirs(dirOf(file));
            writeFile(file, to.s);
            GTEST_SKIP() << "Updating golden master";
        }
        else
        {
            auto expected = readFile(file);
            ASSERT_EQ(to.s, expected);
        }
    }
};

#define CHARACTERIZATION_TEST(NAME, STEM, VALUE)  \
    TEST_F(WorkerProtoTest, NAME ## _read) {   \
        readTest(STEM, VALUE);                 \
    }                                          \
    TEST_F(WorkerProtoTest, NAME ## _write) {  \
        writeTest(STEM, VALUE);                \
    }

CHARACTERIZATION_TEST(
    string,
    "string",
    (std::tuple<std::string, std::string, std::string, std::string, std::string> {
        "",
        "hi",
        "white rabbit",
        "大白兔",
        "oh no \0\0\0 what was that!",
    }))

CHARACTERIZATION_TEST(
    storePath,
    "store-path",
    (std::tuple<StorePath, StorePath> {
        StorePath { "g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-foo" },
        StorePath { "g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-foo-bar" },
    }))

CHARACTERIZATION_TEST(
    contentAddress,
    "content-address",
    (std::tuple<ContentAddress, ContentAddress, ContentAddress> {
        ContentAddress {
            .method = TextIngestionMethod {},
            .hash = hashString(HashType::htSHA256, "Derive(...)"),
        },
        ContentAddress {
            .method = FileIngestionMethod::Flat,
            .hash = hashString(HashType::htSHA1, "blob blob..."),
        },
        ContentAddress {
            .method = FileIngestionMethod::Recursive,
            .hash = hashString(HashType::htSHA256, "(...)"),
        },
    }))

CHARACTERIZATION_TEST(
    derivedPath,
    "derived-path",
    (std::tuple<DerivedPath, DerivedPath> {
        DerivedPath::Opaque {
            .path = StorePath { "g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-foo" },
        },
        DerivedPath::Built {
            .drvPath = makeConstantStorePathRef(StorePath {
                "g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-bar.drv",
            }),
            .outputs = OutputsSpec::Names { "x", "y" },
        },
    }))

CHARACTERIZATION_TEST(
    drvOutput,
    "drv-output",
    (std::tuple<DrvOutput, DrvOutput> {
        {
            .drvHash = Hash::parseSRI("sha256-FePFYIlMuycIXPZbWi7LGEiMmZSX9FMbaQenWBzm1Sc="),
            .outputName = "baz",
        },
        DrvOutput {
            .drvHash = Hash::parseSRI("sha256-b4afnqKCO9oWXgYHb9DeQ2berSwOjS27rSd9TxXDc/U="),
            .outputName = "quux",
        },
    }))

CHARACTERIZATION_TEST(
    realisation,
    "realisation",
    (std::tuple<Realisation, Realisation> {
        Realisation {
            .id = DrvOutput {
                .drvHash = Hash::parseSRI("sha256-FePFYIlMuycIXPZbWi7LGEiMmZSX9FMbaQenWBzm1Sc="),
                .outputName = "baz",
            },
            .outPath = StorePath { "g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-foo" },
            .signatures = { "asdf", "qwer" },
        },
        Realisation {
            .id = {
                .drvHash = Hash::parseSRI("sha256-FePFYIlMuycIXPZbWi7LGEiMmZSX9FMbaQenWBzm1Sc="),
                .outputName = "baz",
            },
            .outPath = StorePath { "g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-foo" },
            .signatures = { "asdf", "qwer" },
            .dependentRealisations = {
                {
                    DrvOutput {
                        .drvHash = Hash::parseSRI("sha256-b4afnqKCO9oWXgYHb9DeQ2berSwOjS27rSd9TxXDc/U="),
                        .outputName = "quux",
                    },
                    StorePath { "g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-foo" },
                },
            },
        },
    }))

CHARACTERIZATION_TEST(
    buildResult,
    "build-result",
    ({
        using namespace std::literals::chrono_literals;
        std::tuple<BuildResult, BuildResult, BuildResult> t {
            BuildResult {
                .status = BuildResult::OutputRejected,
                .errorMsg = "no idea why",
            },
            BuildResult {
                .status = BuildResult::NotDeterministic,
                .errorMsg = "no idea why",
                .timesBuilt = 3,
                .isNonDeterministic = true,
                .startTime = 30,
                .stopTime = 50,
            },
            BuildResult {
                .status = BuildResult::Built,
                .timesBuilt = 1,
                .builtOutputs = {
                    {
                        "foo",
                        {
                            .id = DrvOutput {
                                .drvHash = Hash::parseSRI("sha256-b4afnqKCO9oWXgYHb9DeQ2berSwOjS27rSd9TxXDc/U="),
                                .outputName = "foo",
                            },
                            .outPath = StorePath { "g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-foo" },
                        },
                    },
                    {
                        "bar",
                        {
                            .id = DrvOutput {
                                .drvHash = Hash::parseSRI("sha256-b4afnqKCO9oWXgYHb9DeQ2berSwOjS27rSd9TxXDc/U="),
                                .outputName = "bar",
                            },
                            .outPath = StorePath { "g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-bar" },
                        },
                    },
                },
                .startTime = 30,
                .stopTime = 50,
#if 0
                // These fields are not yet serialized.
                // FIXME Include in next version of protocol or document
                // why they are skipped.
                .cpuUser = std::chrono::milliseconds(500s),
                .cpuSystem = std::chrono::milliseconds(604s),
#endif
            },
        };
        t;
    }))

CHARACTERIZATION_TEST(
    keyedBuildResult,
    "keyed-build-result",
    ({
        using namespace std::literals::chrono_literals;
        std::tuple<KeyedBuildResult, KeyedBuildResult/*, KeyedBuildResult*/> t {
            KeyedBuildResult {
                {
                    .status = KeyedBuildResult::OutputRejected,
                    .errorMsg = "no idea why",
                },
                /* .path = */ DerivedPath::Opaque {
                    StorePath { "g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-xxx" },
                },
            },
            KeyedBuildResult {
                {
                    .status = KeyedBuildResult::NotDeterministic,
                    .errorMsg = "no idea why",
                    .timesBuilt = 3,
                    .isNonDeterministic = true,
                    .startTime = 30,
                    .stopTime = 50,
                },
                /* .path = */ DerivedPath::Built {
                    .drvPath = makeConstantStorePathRef(StorePath {
                        "g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-bar.drv",
                    }),
                    .outputs = OutputsSpec::Names { "out" },
                },
            },
        };
        t;
    }))

CHARACTERIZATION_TEST(
    optionalTrustedFlag,
    "optional-trusted-flag",
    (std::tuple<std::optional<TrustedFlag>, std::optional<TrustedFlag>, std::optional<TrustedFlag>> {
        std::nullopt,
        std::optional { Trusted },
        std::optional { NotTrusted },
    }))

CHARACTERIZATION_TEST(
    vector,
    "vector",
    (std::tuple<std::vector<std::string>, std::vector<std::string>, std::vector<std::string>, std::vector<std::vector<std::string>>> {
        { },
        { "" },
        { "", "foo", "bar" },
        { {}, { "" }, { "", "1", "2" } },
    }))

CHARACTERIZATION_TEST(
    set,
    "set",
    (std::tuple<std::set<std::string>, std::set<std::string>, std::set<std::string>, std::set<std::set<std::string>>> {
        { },
        { "" },
        { "", "foo", "bar" },
        { {}, { "" }, { "", "1", "2" } },
    }))

CHARACTERIZATION_TEST(
    optionalStorePath,
    "optional-store-path",
    (std::tuple<std::optional<StorePath>, std::optional<StorePath>> {
        std::nullopt,
        std::optional {
            StorePath { "g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-foo-bar" },
        },
    }))

CHARACTERIZATION_TEST(
    optionalContentAddress,
    "optional-content-address",
    (std::tuple<std::optional<ContentAddress>, std::optional<ContentAddress>> {
        std::nullopt,
        std::optional {
            ContentAddress {
                .method = FileIngestionMethod::Flat,
                .hash = hashString(HashType::htSHA1, "blob blob..."),
            },
        },
    }))

}
