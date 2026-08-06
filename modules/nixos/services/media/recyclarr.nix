{ config, ... }:

let
  hd1080 = [
    { name = "Bluray-1080p"; }
    {
      name = "WEB 1080p";
      qualities = [
        "WEBDL-1080p"
        "WEBRip-1080p"
      ];
    }
    { name = "Bluray-720p"; }
    {
      name = "WEB 720p";
      qualities = [
        "WEBDL-720p"
        "WEBRip-720p"
      ];
    }
  ];

  uhd2160 = [
     { name = "Bluray-2160p"; }
     {
       name = "WEB 2160p";
       qualities = [
         "WEBDL-2160p"
         "WEBRip-2160p"
       ];
     }
   ]
   ++ hd1080;
in
{
  age.secrets = {
    radarr-api-key.file = ../../../../hosts/shimmers/secrets/radarr-api-key.age;
    sonarr-api-key.file = ../../../../hosts/shimmers/secrets/sonarr-api-key.age;
  };

  services.recyclarr = {
    enable = true;
    schedule = "daily";
    configuration = {
      radarr.movies = {
        base_url = "http://localhost:7878";
        api_key._secret = config.age.secrets.radarr-api-key.path;

        quality_profiles = [
          {
            name = "German";
            reset_unmatched_scores.enabled = true;
            quality_sort = "top";
            min_format_score = 0;
            upgrade = {
              allowed = true;
              until_quality = "Bluray-2160p";
              until_score = 11000;
            };
            qualities = uhd2160;
          }
          {
            name = "Original Language";
            reset_unmatched_scores.enabled = true;
            quality_sort = "top";
            min_format_score = -1000;
            upgrade = {
              allowed = true;
              until_quality = "Bluray-2160p";
              until_score = 0;
            };
            qualities = uhd2160;
          }
        ];

        custom_formats = [
          {
            trash_ids = [ "86bc3115eb4e9873ac96904a4a68e19e" ]; # German
            assign_scores_to = [
              {
                name = "German";
                score = 10000;
              }
              {
                name = "Original Language";
                score = -200;
              }
            ];
          }
          {
            trash_ids = [ "f845be10da4f442654c13e1f2c3d6cd5" ]; # German DL
            assign_scores_to = [
              {
                name = "German";
                score = 11000;
              }
              {
                name = "Original Language";
                score = -100;
              }
            ];
          }
          {
            trash_ids = [ "6aad77771dabe9d3e9d7be86f310b867" ]; # German DL (undefined)
            assign_scores_to = [
              {
                name = "German";
                score = 10000;
              }
              {
                name = "Original Language";
                score = -100;
              }
            ];
          }
          {
            trash_ids = [ "d6e9318c875905d6cfb5bee961afcea9" ]; # Language: Not Original
            assign_scores_to = [
              {
                name = "German";
                score = 0;
              }
              {
                name = "Original Language";
                score = -10000;
              }
            ];
          }
        ];
      };

      sonarr.tv = {
        base_url = "http://localhost:8989";
        api_key._secret = config.age.secrets.sonarr-api-key.path;

        quality_profiles = [
          {
            name = "German";
            reset_unmatched_scores.enabled = true;
            quality_sort = "top";
            min_format_score = 0;
            upgrade = {
              allowed = true;
              until_quality = "Bluray-1080p";
              until_score = 11100;
            };
            qualities = hd1080;
          }
          {
            name = "Original Language";
            reset_unmatched_scores.enabled = true;
            quality_sort = "top";
            min_format_score = -1000;
            upgrade = {
              allowed = true;
              until_quality = "Bluray-1080p";
              until_score = 100;
            };
            qualities = hd1080;
          }
          {
            trash_id = "20e0fc959f1f1704bed501f23bdae76f"; # [Anime] Remux-1080p
            name = "Anime";
            reset_unmatched_scores.enabled = true;
            quality_sort = "top";
            upgrade = {
              allowed = true;
              until_quality = "Bluray-1080p";
              until_score = 10000;
            };
            qualities = hd1080;
          }
        ];

        custom_formats = [
          {
            trash_ids = [ "8a9fcdbb445f2add0505926df3bb7b8a" ]; # German
            assign_scores_to = [
              {
                name = "German";
                score = 10000;
              }
              {
                name = "Original Language";
                score = -200;
              }
            ];
          }
          {
            trash_ids = [ "ed51973a811f51985f14e2f6f290e47a" ]; # German DL
            assign_scores_to = [
              {
                name = "German";
                score = 11000;
              }
              {
                name = "Original Language";
                score = -100;
              }
            ];
          }
          {
            trash_ids = [ "c5dd0fd675f85487ad5bdf97159180bd" ]; # German DL (undefined)
            assign_scores_to = [
              {
                name = "German";
                score = 10000;
              }
              {
                name = "Original Language";
                score = -100;
              }
            ];
          }
          {
            trash_ids = [ "3bc5f395426614e155e585a2f056cdf1" ]; # Season Pack
            assign_scores_to = [
              {
                name = "German";
                score = 100;
              }
              {
                name = "Original Language";
                score = 100;
              }
              {
                name = "Anime";
                score = 10;
              }
            ];
          }
          {
            trash_ids = [ "ae575f95ab639ba5d15f663bf019e3e8" ]; # Language: Not Original
            assign_scores_to = [
              {
                name = "German";
                score = 0;
              }
              {
                name = "Original Language";
                score = -10000;
              }
            ];
          }
        ];
      };
    };
  };

  my.vpn.confinedServices = [ "recyclarr" ];

  environment.systemPackages = [ config.services.recyclarr.package ];
}
