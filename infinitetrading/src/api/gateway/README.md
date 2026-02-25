Here's how you can structure your README.md file for the API gateway setup and management of the Infinite Trading v1 API:

```markdown
# Infinite Trading API v1 Gateway Configuration

This README details the process for adding new endpoints to the Infinite Trading API v1 gateway. Follow these steps carefully to ensure that the new endpoints are integrated correctly and the API functions as expected.

## Adding New Endpoints

To add new endpoints to the Infinite Trading API gateway, follow these steps:

### 1. Define the Endpoint

- Go to `../helpers/endpoints.R` and manually add the name of the new endpoint, for example, `"newEndpoint"`.

### 2. Create Gateway Endpoint

- Create the file for the new endpoint at `gateway/endpoints/newEndpoint.R`.
- In this file, define the gateway function. This function will route the requests to the appropriate server, which can be either the Express server on port 8000 or the Plumber endpoint.

### 3. Program the Endpoint

- The programming for the new endpoint should be added to `../api.R`. This file contains the logic that the gateway will use to process requests.

### 4. Database Interaction

- If the new endpoint interacts with a database, create a function named `newEndpoint()` in the `db.R` file. This function will handle database read/write operations.
- If the endpoint does not require database interaction, you can handle data operations directly within the endpoint file.

### 5. Update Nginx Configuration

- Open the Nginx configuration file at `/etc/nginx/sites-enabled/api.infinitetrading.io`.
- Add the new endpoint to the existing list of gateway endpoints using this structure (endpoint1|endpoint2|newEndpoint).

### 6. Reload Nginx

- To apply the changes, reload the Nginx configuration by running:
  ```bash
  sudo nginx -s reload
  ```

### 7. Restart API Services

- To ensure the changes take effect, restart the main Plumber API and the Gateway:
  - Attach to the Plumber screen:
    ```bash
    screen -r plumber
    ```
  - Press `CTRL+C` once to stop the Plumber API, then press `CTRL+A` followed by `D` to detach from the screen.
  - Repeat the process for the Gateway:
    ```bash
    screen -r gateway
    CTRL+C
    CTRL+A+D
    ```

## Conclusion

After completing these steps, your new API endpoint should be fully integrated and operational. Make sure to test the endpoint to ensure it functions as expected and handles all intended operations correctly.
```

