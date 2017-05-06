#!/bin/sh

set -e

image_name="traefik"

usage() {
	cat 1>&2 <<EOUSAGE

This script builds the $image_name base image.

   usage: $mkimg [-t tag] [-l | --latest] [-e | --edge]
      ie: $mkimg -t somerepo/$image_name:3.2.8 -l

  builds: somerepo/$image_name:3.2.8
          somerepo/$image_name:latest

EOUSAGE
exit 1
}

semver_parse() {
  version_major="${1%%.*}"
	version_minor="${1#$version_major.}"
	version_minor="${version_minor%%.*}"
	version_patch="${1#$version_major.$version_minor.}"
	version_patch="${version_patch%%[-.]*}"
}

image_parse() {
  repo="${1%%\/*}"
  image="${1#$repo\/}"
  image="${image%%\:*}"
  tag="${1#$repo\/$image\:}"

  build_base=''
  if [ -n "${repo}" ]; then
    build_base="${repo}/${image}"
  else
    build_base="${image}"
  fi

  build_name="${build_base}:${tag}"
}

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

check_deps() {
  # Make sure a base/alpine image is available and usable on the system.
  base_image="${BASE_IMAGE:-base/alpine:3.5.0}"
  base_image_exists=$( docker images | grep "${base_image%%\:[0-9].*}" )

  if [ ! "${base_image_exists}" ]; then
    cat 1>&2 <<-EOF
		Error: Could not find base image.
		Build the "${base_image}" image before building this image.

				sh mkimage.sh alpine -t ${base_image}

		EOF
    exit 1
  fi

  # Make sure a base/golang image is available and usable on the system.
  golang_image_exists=$( docker images | grep base/golang )

  if [ ! "${golang_image_exists}" ]; then
    cat 1>&2 <<-EOF
		Error: Could not find golang image.
		Build the base/golang:1.8 image before building this image.

    NOTE: The golang image can be removed once the build process is complete.

		    sh mkimage.sh golang -t base/golang:1.8

		EOF
    exit 1
  fi
}

check_docker() {
  command_exists docker
  docker_exists=$?
  if [ ! "${docker_exists}" ]; then
    cat 1>&2 <<-EOF
		Error: Could not find docker on your system.
		Make sure docker is installed and try again.

		You can install docker using:

				curl -sSL https://get.docker.com/ | sh

		EOF
    exit 1
  fi

  # Docker is installed. Check that version is greater than 17.05.
  docker_version="$( docker -v | cut -d ' ' -f3 | cut -d ',' -f1 )"
  cat <<-EOF
	Docker version: ${docker_version}
	EOF

  # Parse the version into major/minor/patch.
  semver_parse ${docker_version}

  # docker_version=$( docker -v | sed -n 's/^.*\(\ [0-9]\+\.[0-9]\+\).*$/\1/p' )
  # docker_semver_major=$( echo ${docker_version} | sed -n 's/^\(\<[0-9]\+\>\).*$/\1/p' )
  # version_minor=$( echo ${docker_version} | sed -n 's/^.*\(\<[0-9]\+\>\)$/\1/p' )

  need_upgrade=0

  # Ensure the docker version is high enough to support multi-stage builds.
  # Multi-stage builds are a Docker feature since 17.05.
  if [ "${version_major}" -lt 17 ]; then
    need_upgrade=1
  elif [ "${version_major}" -eq 17 ] && [ "${version_minor}" -lt 5 ]; then
    need_upgrade=1
  fi

  # If the Docker version is too low to support multi-stage builds, post an
  # error and exit.
  if [ "${need_upgrade}" -eq 1 ]; then
    cat 1>&2 <<-EOF
		Error: Docker ${docker_version} does not support multi-stage builds.
		Install a newer version of Docker and try again.

		You can install a more recent version of docker using:

				curl -sSL https://get.docker.com/ | sh

		EOF
    exit 1
  fi

}

make_image() {

  tmp=$( mktemp -d /tmp/${image_name}.XXXXXX )

  if [ "${tag}" = "latest" ]; then
    cat 1>&2 <<-EOF
		Error: Invalid tag.
		To tag the image as 'latest', use the '-l' flag.
		EOF
    exit 1
  elif [ "${tag}" = "edge" ]; then
    cat 1>&2 <<-EOF
		Error: Invalid tag.
		To tag the image as 'edge', use the '-e' flag.
		EOF
    exit 1
  fi

  semver_parse "${tag}"

  # ----------------------------------------
  # Build the golang image.
  # ----------------------------------------

  # Template Dockerfile to use environment variables.
  version=${tag}
  checksum=$(grep " traefik-$version.tar.gz\$" traefik/SHASUMS256.txt)

  cat ${mkimg_dir}/traefik/Dockerfile | \
    sed -e "s@\${base_image}@${base_image}@" | \
    sed -e "s@\${version}@${version}@" | \
    sed -e "s@\${checksum}@${checksum}@" \
    > ${tmp}/Dockerfile

  # Copy necessary build files.
  cp ${mkimg_dir}/traefik/docker-entrypoint.sh ${tmp}/docker-entrypoint.sh

  # Docker build.
  docker build \
    -t ${build_name} ${tmp}
  docker_exit_code=$?

  if [ "${docker_exit_code}" -ne 0 ]; then
    cat 1>&2 <<-EOF
		Error: Docker build failed.
		Docker failed with exit code ${docker_exit_code}
		EOF
    exit 1
  fi

  if [ "${latest}" -eq 1 ]; then
    docker tag ${build_name} "${build_base}:latest"
  fi

  if [ "${edge}" -eq 1 ]; then
    docker tag ${build_name} "${build_base}:edge"
  fi
}

# Placeholder to determine if the version is the latest tag.
latest=0
edge=0

# Parse options/flags.
mkimg="$(basename "$0")"
mkimg_dir="$(dirname "$0")"

options=$(getopt --options ':t:le' --longoptions 'tag:,latest,edge,help' --name "${mkimg}" -- "$@")
eval set -- "${options}"

# Handle arguments/flags.
while true; do
	case "$1" in
		-t|--tag )
      image_parse "$2" ; shift 2 ;;
    -l|--latest )
      latest=1 ; shift ;;
    -e|--edge )
      edge=1 ; shift ;;
		-h|--help )
      usage ;;
		-- )
      shift ; break ;;
	esac
done

# Check for dependencies.
check_docker
check_deps

# Build the image.
make_image
