package com.georgegxx.orders_service.config;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

class Cve202691403MitigationTest {

    private static final Set<String> EMUDHRA_COMPROMISED_INTERMEDIATE_SHA256 = Set.of(
            "0164D7CEAE5BB909C272AF151FF44B1177AE9B47D9424B94F1D9558C30934D19", // EM DV TLS CA - G3C (emSign)
            "42C4ACCD12C4F59597925E1A08A7A90102608543809308D50EC427E118BA1493", // EM DV TLS CA - G3B (emSign)
            "432EC25F0D28DE9006D97BF752F17BBB2CD41F669933FCB072D9A1148D0261F3", // EM EV TLS CA - G3C (emSign)
            "45A883F349AEDFD5F3A649B5498FFB121712BA8B448F3F2A91DBC5A766FCDDBE", // EM DV TLS CA - G3B (Sectigo AAA)
            "4B2460A466F95FD40113BCDCCA2CEB29B3B093921DE45474DA7DF48874C630B1", // EM OV CS CA - G3C (emSign)
            "579480AEA166290BD3C643589E795FC0D0E54E86505D180F1DFF99EFD3199512", // EM EV TLS CA - G3B (Sectigo AAA)
            "5F1DED4DD590AF74631290CF073B122A2AAC6A1FA479778A0BD43579BD832699", // EM OV TLS CA - G3B (Sectigo AAA)
            "62B7F9868263F72F6911FC78CEAF72C1979158B7368BF648683BB2AA39B02E72", // EM DV TLS CA - G3C (Sectigo AAA)
            "7485B51C0ED192878FA1D2F948FB529AE1842CC5086C4B67F7BE5B2039DE9489", // EM OV TLS CA - G3C (Sectigo AAA)
            "84112972B8E59D14560AE7E7119654474AAD119990CF3722BFC1E3B91615E1FD", // EM OV CS CA - G3C (Sectigo AAA)
            "98B896625C0C230ADEEC3EB2CF6AAD5001ECF9156A68644E82374CE5833BC25B", // EM OV TLS CA - G3B (emSign)
            "9E39DE2881273ACC225A149C72BA3E0F51424963669AB633EE1DC7DF5DB067B4", // EM OV CS CA - G3B (emSign)
            "A496E23AC0CAB8155FC9B117B97EAE368EFCBB9041AEC8804D5A308D2D01C2D8", // EM OV CS CA - G3B (Sectigo AAA)
            "CB6E15165AC802E9B3F993F16C25D41F4E81C21EBDE71AE1B012AC00BF9C7C3F", // EM OV TLS CA - G3C (emSign)
            "E7568FE6E12331F4FD7DE61DA4C7559D0F8EB192A218D4741A3BA75184333838", // EM EV TLS CA - G3B (emSign)
            "FD9D5C2DBBD4995AB69B8D50C439D9527B00529199C2FD01B2174EB58F07021F"  // EM EV TLS CA - G3C (Sectigo AAA)
    );

    @Test
    void blockedCertsContainsAllSixteenCompromisedEmudhraIntermediates() throws Exception {
        Path blockedCertsPath = resolveBlockedCertsPath();
        assertThat(blockedCertsPath).exists();

        List<String> lines = Files.readAllLines(blockedCertsPath).stream()
                .map(line -> line != null ? line.trim() : "")
                .filter(line -> !line.isEmpty())
                .toList();

        assertThat(lines).isNotEmpty();
        assertThat(lines.getFirst()).isEqualTo("Algorithm=SHA-256");

        Set<String> fingerprints = lines.stream()
                .skip(1)
                .collect(Collectors.toSet());

        assertThat(fingerprints)
                .allMatch(fp -> fp.matches("^[0-9A-F]{64}$"))
                .containsAll(EMUDHRA_COMPROMISED_INTERMEDIATE_SHA256);
    }

    @Test
    void surefireEnforcesTlsCertificateRevocationCheckingProperties() {
        assertThat(System.getProperty("com.sun.net.ssl.checkRevocation")).isEqualTo("true");
        assertThat(System.getProperty("com.sun.security.enableCRLDP")).isEqualTo("true");
    }

    private static Path resolveBlockedCertsPath() {
        Path containerPath = Path.of("/app", "security", "blocked.certs");
        if (Files.exists(containerPath)) {
            return containerPath;
        }
        Path fromModule = Path.of("..", "devsecops", "compliance", "java-security", "blocked.certs");
        if (Files.exists(fromModule)) {
            return fromModule;
        }
        return Path.of("devsecops", "compliance", "java-security", "blocked.certs");
    }
}
