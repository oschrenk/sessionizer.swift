{
  description = "Sessionizer.app - a Liquid Glass picker that opens projects in Ghostty";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.aarch64-darwin;
    in
    {
      # mkShellNoCC, not mkShell: a cc-wrapper exports SDKROOT/DEVELOPER_DIR
      # pointing at nixpkgs' apple-sdk, which Xcode's swiftc refuses. No swift
      # from nixpkgs either: the package needs the Xcode 27 toolchain and SDK.
      devShells.aarch64-darwin.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          swiftformat
          swiftlint
          go-task
        ];
        shellHook = ''
          unset SDKROOT DEVELOPER_DIR MACOSX_DEPLOYMENT_TARGET
        '';
      };
    };
}
