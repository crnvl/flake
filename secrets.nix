let
  shimmers = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOs1x+98r+MXYAitek6+yrO96TnyOWoZ9IO6MPONqcmY";

  # Your user keys
  aleph-chambers = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH++Jm6a+gQf5yEdTzT5ozuIQdkYb2w98UxsX2I1YJlg";
  aleph-corridors = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIXBwAlJ0BxHk01MZ5QnVHbmS5tgO+Rubg0MyJsIk5dp";
  aleph-macbook = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICbVo7Bj9I6oZc8cM4IPDNhF6MSns8X8S8HrVhql/PxV";

  users = [
    aleph-chambers
    aleph-corridors
    aleph-macbook
  ];
in
{
  "hosts/shimmers/secrets/kanidm-idm-admin-password.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/kanidm-admin-password.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/kanidm-oauth2-jellyfin-secret.age".publicKeys = users ++ [ shimmers ];
}
