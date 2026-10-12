{
  description = "opendebate-cab: the club cabinet and the engine client";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      project_name = "opendebate-cab";
      pkgs = import nixpkgs { inherit system; };
      erlang = pkgs.beam.packages.erlang_27.erlang;
      elixir = pkgs.beam.packages.erlang_27.elixir;
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.fswatch
          erlang
          elixir
          pkgs.beamPackages.expert
          pkgs.postgresql
          pkgs.nodejs_22
          pkgs.vscode-langservers-extracted
          pkgs.pnpm
          pkgs.prettier
        ];
        shellHook = ''
          export PG=$PWD/.dev_postgres
          export PGDATA=$PG/data
          export PGPORT=5433
          export PGHOST=localhost
          export PGUSER=$USER
          export LANG="en_US.UTF-8"
          export ERL_AFLAGS="-kernel shell_history enabled"
          export MIX_HOME=$PWD/.mix
          export HEX_HOME=$PWD/.hex
          export PATH=$MIX_HOME/bin:$MIX_HOME/escripts:$PATH

          alias mix_start='source .env && mix phx.server'
          alias ..='cd ..'
          alias ...='cd ../..'
          alias ....='cd ../../..'
          alias h='history'
          alias c='clear'
          alias tree='tree -C'
          # pg_setup bootstraps the shared local cluster only; each app's
          # database is owned by its Ecto config (mix ecto.setup creates,
          # migrates and seeds it). One instance, a separate database
          # per service.
          alias pg_setup="initdb -D $PGDATA && \
            echo \"unix_socket_directories = '$PGDATA'\" >> $PGDATA/postgresql.conf && \
            pg_start && \
            createdb"
          # run ecto.setup in every phoenix app (from apps/)
          alias ecto_setup_all='for d in */; do \
            [ -f "$d/mix.exs" ] && (cd "$d" && mix ecto.setup); done; true'
          alias pg_stop='pg_ctl -D $PGDATA stop'
          alias pg_start='pg_ctl -D $PGDATA -l $PG/postgres.log start'
        '';
      };
    };
}
