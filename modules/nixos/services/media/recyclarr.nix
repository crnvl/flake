{ config, ... }:

{
  age.secrets.radarr-api-key.file = ../../../../hosts/shimmers/secrets/radarr-api-key.age;

  services.recyclarr = {
    enable = true;
    schedule = "daily";
    configuration = {
      radarr.main = {
        base_url = "http://localhost:7878";
        api_key._secret = config.age.secrets.radarr-api-key.path;

        quality_profiles = [ { name = "German"; } ];

        custom_formats = [
          {
            trash_ids = [ "86bc3115eb4e9873ac96904a4a68e19e" ]; # German
            assign_scores_to = [
              {
                name = "German";
                score = 10000;
              }
            ];
          }
          {
            trash_ids = [ "f845be10da4f442654c13e1f2c3d6cd5" ]; # German DL (both audio)
            assign_scores_to = [
              {
                name = "German";
                score = 11000;
              }
            ];
          }
        ];
      };
    };
  };

  systemd.services.recyclarr.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg";
  };
}
