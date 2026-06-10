{ customTop, inputs, ... }:
{
  flake.modules.nixos.hermes-webui =
    { config, pkgs, ... }:
    let
      # Define the python environment with necessary dependencies
      pythonEnv = pkgs.python3.withPackages (
        ps: with ps; [
          pyyaml
          cryptography
          # Optional: edge-tts for voice support
          edge-tts
        ]
      );

      # Use the flake input for the application source code
      hermesWebUI = inputs.hermes-webui;

    in
    {
      # Wczytujemy hermes-env.age jako sekret współdzielony z hermes-agent
      age.secrets.hermes-webui-env = {
        file = customTop.secretsDir + "/hermes-env.age";
        owner = "hermes";
        group = "hermes";
        mode = "0400";
      };

      # Systemd service to run the Hermes WebUI server
      systemd.services.hermes-webui = {
        description = "Hermes WebUI Server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        serviceConfig = {
          Type = "simple";
          User = "hermes";
          Group = "hermes";
          WorkingDirectory = hermesWebUI;
          # Run the server.py using our controlled python environment
          ExecStart = "${pythonEnv}/bin/python server.py";
          Restart = "always";
          RestartSec = "10";

          # Load the password and any other env vars from agenix
          EnvironmentFile = config.age.secrets.hermes-webui-env.path;

          # Hardcoded Environment variables
          # Since it's a native Nix setup, we bind to 127.0.0.1 for the tunnel
          Environment = [
            "HOST=127.0.0.1"
            "PORT=8787"
            "HERMES_AGENT_API_URL=http://127.0.0.1:8642"
          ];
        };
      };
    };
}
