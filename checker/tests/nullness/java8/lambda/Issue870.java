// Test case for issue #870: https://github.com/typetools/checker-framework/issues/870
// @skip-test until it is fixed
// @below-java8-jdk-skip-test

import java.util.stream.Stream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public class Issue870 {
    public static Stream<? extends ZipEntry> entries(ZipFile zipFile) {
        return zipFile.stream()
                .filter(entry -> !entry.isDirectory() && entry.getName().endsWith(".xml"));
    }

    public static Stream<? extends ZipEntry> entries2(ZipFile zipFile) {
        return zipFile.stream()
                .filter(
                        (ZipEntry entry) ->
                                !entry.isDirectory() && entry.getName().endsWith(".xml"));
    }
}
