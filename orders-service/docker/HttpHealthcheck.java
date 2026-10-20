import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;

/** Minimal HTTP health probe for distroless Java images. */
public final class HttpHealthcheck {
    private HttpHealthcheck() {}

    public static void main(String[] args) {
        if (args.length != 1) {
            System.exit(2);
        }

        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) URI.create(args[0]).toURL().openConnection();
            connection.setRequestMethod("GET");
            connection.setConnectTimeout(3000);
            connection.setReadTimeout(3000);
            int status = connection.getResponseCode();
            byte[] response = connection.getInputStream().readAllBytes();
            String body = new String(response, StandardCharsets.UTF_8);
            if (status != HttpURLConnection.HTTP_OK || !body.contains("\"status\":\"UP\"")) {
                System.exit(1);
            }
        } catch (Exception exception) {
            System.exit(1);
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }
}
