# HinD - Hashistack-in-Docker
```diff
+       ___                                              ·
+      /\  \                      ___                    ·
+      \ \--\       ___          /\  \        __ __      ·
+       \ \--\     /\__\         \ \--\     / __ \__\    ·
+   ___ /  \--\   / /__/     _____\ \--\   / /__\ \__\   ·
+  /\_ / /\ \__\ /  \ _\    / ______ \__\ / /__/ \ |__|  ·
+  \ \/ /_ \/__/ \/\ \ _\__ \ \__\  \/__/ \ \__\ / /__/  ·
+   \  /__/         \ \/\__\ \ \__\        \ \__/ /__/   ·
+    \ \ _\          \  /_ /  \ \__\        \ \/ /__/    ·
+     \ \__\         / /_ /    \/__/         \  /__/     ·
+      \/__/         \/__/                    \/__/      ·
+                                                        ·
```

![install](img/install.gif)



Installs `nomad`, `consul`, and `caddyserver` (router) together as a mini cluster running inside a `docker` container.

Nomad jobs will run as `docker` containers on the VM itself, orchestrated by `nomad`, leveraging `docker.sock`.

The _brilliant_ `consul-template` will be used as "glue" between `consul` and `caddyserver` -- turning `caddyserver` into an always up-to-date reverse proxy router from incoming requests' Server Name Indication (SNI) to running containers :)

## Setup and run
This will "bootstrap" your cluster with a private, unique `NOMAD_TOKEN`,
and `docker run` a new container with the hind service into the background.

```bash
docker run --net=host --privileged -v /var/run/docker.sock:/var/run/docker.sock \
  -e FQDN=$(hostname -f) -e HOST_UNAME=$(uname) \
  --rm --name hind --pull=always ghcr.io/internetarchive/hind:main
```

## Minimal requirements:
- VM you can `ssh` into
- VM with `docker` daemon
- if using a firewall (like `ferm`, etc.) make sure the following ports are open from the VM to the world:
  - 443  - https
  - 80   - http  (load balancer will auto-upgrade/redir to https)
@see [#VM-Administration](#VM-Administration) section for more info.

## https
The ideal experience is that you point a dns wildcard at the IP address of the VM running your `hind` system.

This allows automatically-created hostnames from CI/CD pipelines [deploy] stage to use the [git group/organization + repository name + branch name] to create a nice semantic DNS hostname for your webapps to run as and load from - and everything will "just work".

For example, `*.example.com` DNS wildcard pointing to the VM where `hind` is running, will allow https://myteam-my-repo-name-my-branch.example.com to "just work".

We use [caddy](https://caddyserver.com) (which incorporates `zerossl` and Let's Encrypt) to on-demand create single host https certs as service discovery from `consul` announces new hostnames.



### build locally - if desired (not required)
This is our [Dockerfile](Dockerfile)

```bash
git clone https://github.com/internetarchive/hind.git
cd hind
docker build --network=host -t ghcr.io/internetarchive/hind:main .
```


## Setting up jobs
We suggest you use the same approach mentioned in
[nomad repo README.md](https://gitlab.com/internetarchive/nomad/-/blob/master/README.md)
which will ultimately use a templated
[project.nomad](https://gitlab.com/internetarchive/nomad/-/blob/master/project.nomad) file.


## Nicely Working Features
We use this in multiple places for one-off "clusters of one" at archive.org.
We pair it with our fully templatized
[project.nomad](https://gitlab.com/internetarchive/nomad/-/blob/master/project.nomad)
Working nicely:
- secrets, tokens
- persistent volumes
- deploys with multiple public ports
- and more!  -- just about everything [here](https://gitlab.com/internetarchive/nomad/-/blob/master/README.md#customizing)

## Nomad credentials
Get your nomad access credentials so you can run `nomad status` anywhere
that you have downloaded `nomad` binary (include home mac/laptop etc.)

From a shell on your VM:
```bash
eval $(docker run --rm hind cat /etc/hind)
env |egrep ^NOMAD_
```
Then, `nomad status` should work.
([Download `nomad` binary](https://www.nomadproject.io/downloads) to VM or home dir if/as needed).

You can also open the `NOMAD_ADDR` (above) in a browser and enter in your `NOMAD_TOKEN`

You can try a trivial website job spec from the cloned repo:
```bash
# you can manually set NOMAD_VAR_BASE_DOMAIN to your wildcard DNS domain name if different from
# the domain of your NOMAD_ADDR
export NOMAD_VAR_BASE_DOMAIN=$(echo "$NOMAD_ADDR" |cut -f2- -d.)
nomad run https://raw.githubusercontent.com/internetarchive/hind/main/etc/hello-world.hcl
```

## Optional ways to extend your setup
Here are a few environment variables you can pass in to your intitial `docker run` above, eg: `docker run -e NFSHOME=1 ...`
- `NFSHOME=1`
  - setup /home/ r/o and r/w mounts
- `TRUSTED_PROXIES=[CIDR IP RANGE]`
  - optionally allow certain `X-Forwarded-*` headers, otherwise defaults to `private_ranges`
    [more info](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#trusted_proxies)
- `UNKNOWN_SERVICE_404=[URL]`
  - url to auto-redirect to for unknown service hostnames
  - defaults to: https://archive.org/about/404.html
- `NOMAD_ADDR_EXTRA=[HOSTNAME]`
  - For 1+ extra, nicer https:// hostname(s) you'd like to use to talk to nomad,
    pass in hostname(s) in CSV format for us to setup.
- `REVERSE_PROXY=[HOSTNAME]:[PORT]`
  - For 1+ extra, nicer https:// or https:// hostname(s) to insert into `reverse_proxy` mappings
    to internal ports (CSV format).
    This is helpful if you have additional backends you want proxy rules added into the Caddy config.
    Examples:
    - `-e REVERSE_PROXY=example.com:81` - make https://example.com & http://example.com (with auto-upgrade) reverse proxy to localhost:81
    - `-e REVERSE_PROXY=https://example.com:81` - make https://example.com reverse proxy to localhost:81
    - `-e REVERSE_PROXY=http://example.com:81` - make http://example.com reverse proxy to localhost:81
    - `-e REVERSE_PROXY=https://example.com:82,http://example.com:82` - make https://example.com reverse proxy to localhost:82; http://example.com reverse proxy to localhost:82 (no auto-upgrade)
- `ON_DEMAND_TLS_ASK=[URL]` - If you want to use caddy 'on_demand_tls', URL to use to respond 200/400
                              @see https://caddy.community/t/11179



## GUI, Monitoring, Interacting
- see [nomad repo README.md](https://gitlab.com/internetarchive/nomad/-/blob/master/README.md) for lots of ways to work with your deploys.  There you can find details on how to check a deploy's status and logs, `ssh` into it, customized deploys, and more.
- You can setup an `ssh` tunnel thru your VM so that you can see `consul` in a browser, eg:

```bash
nom-tunnel () {
  [ "$NOMAD_ADDR" = "" ] && echo "Please set NOMAD_ADDR environment variable first" && return
  local HOST=$(echo "$NOMAD_ADDR" |sed 's/^https*:\/\///')
  ssh -fNA -L 8500:localhost:8500 $HOST
}
```

- Then run `nom-tunnel` and you can see with a browser:
  - `consul` http://localhost:8500/


## Add more Virtual Machines to make a HinD cluster
The process is very similar to when you setup your first VM.
This time, you pass in some environment variables, the first VM's hostname (already in cluster),
and run the shell commands below on your 2nd (or 3rd, etc.) VM.

```sh
FIRST=vm1.example.com
set -u
TOK_C=$(ssh $FIRST "docker exec hindup zsh -c 'grep -E ^encrypt.= /etc/consul.d/consul.hcl'" |cut -f2- -d= |tr -d '\t "{}')
TOK_N=$(ssh $FIRST "docker exec hindup zsh -c 'grep -E  encrypt.= /etc/nomad.d/nomad.hcl'"   |cut -f2- -d= |tr -d '\t "{}' )

docker run --net=host --privileged -v /var/run/docker.sock:/var/run/docker.sock \
  -e FIRST  -e TOK_C  -e TOK_N \
  -e FQDN=$(hostname -f) -e HOST_UNAME=$(uname) \
  --rm --name hind --pull=always ghcr.io/internetarchive/hind:main
```


## Inspiration
Docker-in-Docker (dind) and `kind`:
- https://kind.sigs.k8s.io/

for `caddyserver` + `consul-connect`:
- https://blog.tjll.net/too-simple-to-fail-nomad-caddy-wireguard/


## VM Administration
Here are a few helpful admin scripts we use at archive.org
-- some might be helpful for setting up your VM(s).

- [bin/install-docker-ce.sh](bin/install-docker-ce.sh) if no docker yet on your VM
- [bin/ports-unblock.sh](bin/ports-unblock.sh) firewalls - we use `ferm` and here you can see how we
                                   open the minimum number of HTTP/TCP/UDP ports we need to run.
- [bin/install-ctop.sh](bin/install-ctop.sh) `ctop` - a really nice container monitoring
                                   more specialized version of `top` https://github.com/bcicen/ctop
- [bin/setup-pv-using-nfs.sh](bin/setup-pv-using-nfs.sh) we tend to use NFS to share a `/pv/` disk
                                   across our nomad VMs (when cluster is 2+ VMs)
- [bin/setup-consul-dns.sh](bin/setup-consul-dns.sh) - consul dns name resolving --
                                   but we aren't using this yet
```sh
# avoid death by `docker pull` timeout nomad kills relooping and destroying i/o throughput
echo '{ "max-download-attempts": 1 }' >| sudo tee /etc/docker/daemon.json
```


## Problems?
- If the main `docker run` is not completing, check your `docker` version to see how recent it is.  The `nomad` binary inside the setup container can segfault due to a perms change.  You can either _upgrade your docker version_ or try adding this `docker run` option:
```sh
docker run --security-opt seccomp=unconfined ...
```
