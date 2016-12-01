# tab space is 4
# GitHub viewer defaults to 8, change with ?ts=4 in URL

# Vars describing project
# TODO: reconcile the VERSION / REVISION with version_info generation
NAME							= project_name
SERVICE							= project_service_name
ARCH							= x86_64
TARGET							= target
GIT_REPOSITORY					= github.com/TuneDB/project_name
GIT_REPOSITORY_URL				= https://github.com/TuneDB/project_name

# Get the absolute paths
ROOT_PATH						:= $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
TARGET_PATH						= $(ROOT_PATH)/$(TARGET)

# Vars for export container mount, common among phases
EXPORT_PATH						= /export
EXPORT_CONTAINER_MOUNT			= $(TARGET_PATH):$(EXPORT_PATH)


# Generate vars to be included from external script
# Allows using bash to generate complex vars, such as project versions
GENERATE_VERSION_INFO_SCRIPT	= ./generate_version_info.sh
GENERATE_VERSION_INFO_OUTPUT	= version_info

# Define newline needed for subsitution to allow evaluating multiline script output 
define newline


endef

# Call the version_info script with keyvalue option and evaluate the output
# Will import the keyvalue pairs and make available as Makefile variables
# Use dummy variable to only have execute once
$(eval $(subst #,$(newline),$(shell $(GENERATE_VERSION_INFO_SCRIPT) keyvalue | tr '\n' '#')))

# Call the verson_info script with json option and store result into output file and variable
# Will only execute once due to ':='
GENERATE_VERSION_INFO			:= $(shell $(GENERATE_VERSION_INFO_SCRIPT) json | tee $(GENERATE_VERSION_INFO_OUTPUT))

# Set defaults for needed vars in case version_info script did not set
# Revision set to number of commits ahead
VERSION							?= 0.0
COMMITS							?= 0
REVISION						?= $(COMMITS)
BUILD_LABEL						?= unknown_build
BUILD_DATE						?= $(shell date -u +%Y%m%d.%H%M%S)
GIT_SHA1						?= unknown_sha1

# Common things with phases
# Each image will be tagged with the same repository, different tag for phase
#
# Build image is used for providing build environment for project, contains
# the development headers and libraries necessary
#
# Release image provides runtime environment for artifact, typically much smaller
# requirements than build environment.
#
# _id files could be used to indicate if image has been built before
# Usage is commented out currently, images will always be rebuilt if explicitly called
# and images should already be available from accessible registries
# TODO: Find way to dynamically check local registry if image is built

# Vars for export ; generate list of ENV vars based on matching export prefix
# Use strip to get rid of excessive spaces due to the foreach / filter / if logic
EXPORT_VAR_PREFIX               = EXPORT_VAR_
EXPORT_VARS                     = $(strip $(foreach v,$(filter $(EXPORT_VAR_PREFIX)%,$(.VARIABLES)),$(if $(filter environment%,$(origin $(v))),$(v))))

# Vars from commandline; pass long to make calls in containers
MAKE_COMMANDLINE_VARS			= $(strip $(foreach v,$(.VARIABLES),$(if $(filter command line,$(origin $(v))),$(v)=$(value $(value v)))))

# Vars for build phase
#
# Dockerfile for build image included just for completeness for custom build images
# Current values for doing golang build using public available golang container
#
# Will build the project inside the build container and copy the artifact out
# to the target directory of the project on the host
#
# tar of object and /etc/ssl is created to allow creation of a minimal release container
BUILD_IMAGE						= golang:1.4
BUILD_DOCKERFILE				= ./dockerfiles/build/Dockerfile
# BUILD_IMAGE_ID					= build_image_id
# name and location of object inside build container
BUILD_IMAGE_OBJECT				= $(NAME)
BUILD_IMAGE_OBJECT_PATH			= /go/bin/$(BUILD_IMAGE_OBJECT)
# name of object in target directory 
BUILD_OBJECT					= $(NAME)
BUILD_RELEASE_TAR				= $(NAME).tar
# need to tar the binary from the target (export inside container) and root ssl certs for release container
BUILD_RELEASE_TAR_OBJECTS		= $(EXPORT_PATH)/$(BUILD_OBJECT) /etc/ssl
# locations and mounts to be used inside build container
BUILD_IMAGE_GOPATH				= /go
BUILD_IMAGE_PROJECT_PATH		= $(BUILD_IMAGE_GOPATH)/src/$(GIT_REPOSITORY)
BUILD_IMAGE_CONTAINER_MOUNT		= $(ROOT_PATH):$(BUILD_IMAGE_PROJECT_PATH)
# build list of ENV vars to pass into container from host
BUILD_IMAGE_ENV_VARS            = $(foreach v,$(EXPORT_VARS),-e $(v))

# Vars for release phase
#
# Use the Dockerfile defined for the release container in the project
RELEASE_IMAGE_REPOSITORY		= tune.com/tunedb/$(NAME)
RELEASE_DOCKERFILE				= ./dockerfiles/release/Dockerfile
# RELEASE_IMAGE_ID				= release_image_id
# name of tar for when exporting release container to disk 
RELEASE_IMAGE_TAR				= $(NAME).image.tar
RELEASE_IMAGE_TAG_UNIQUE		= $(BUILD_DATE)-$(GIT_SHA1)
RELEASE_IMAGE_TAG_NICE			= $(VERSION:v%=%)-$(REVISION)-$(LABEL)
RELEASE_IMAGE_TAG_LATEST		= latest

# Vars for rpm phase
RPMBUILD_IMAGE					= tune.com/tunedb/rpmbuild
RPMBUILD_DOCKERFILE				= ./dockerfiles/rpm/Dockerfile
# RPMBUILD_IMAGE_ID				= rpm_image_id
# Strip the leading v from version if present
RPM_VERSION						= $(VERSION:v%=%)
RPM_REVISION					= $(REVISION)
RPM_REAL_NAME					= $(SERVICE)
RPM_SERVICE_NAME				= $(SERVICE)
RPM_BINARY_FILE					= $(BUILD_OBJECT)
RPM								= has-$(SERVICE)-$(VERSION)-$(REVISION).$(ARCH).rpm
# paths and mounts inside the rpmbuild container
RPM_IMAGE_PATH					= ~/rpmbuild/RPMS/$(ARCH)/$(RPM)
RPMBUILD_IMAGE_RPMBUILD_PATH	= /root/rpmbuild
# mount the single build object; could mount the whole target directory if spec file expects it
RPMBUILD_IMAGE_SOURCES_MOUNT	= $(TARGET_PATH)/$(BUILD_OBJECT):$(RPMBUILD_IMAGE_RPMBUILD_PATH)/SOURCES/$(BUILD_OBJECT)
# mount the spec directory included in the project
RPMBUILD_IMAGE_SPECS_MOUNT		= $(ROOT_PATH)/rpm/SPECS:$(RPMBUILD_IMAGE_RPMBUILD_PATH)/SPECS
# mount the target directory to the rpm output directory in the container
RPMBUILD_IMAGE_RPMS_MOUNT		= $(TARGET_PATH):$(RPMBUILD_IMAGE_RPMBUILD_PATH)/RPMS

# Vars for tarball phase (building tarball of binary)
TARBALL_FILENAME				= $(BUILD_LABEL)
TARBALL_OBJECTS					= $(BUILD_OBJECT)

# Vars for go phase
# All vars which being with prefix will be included in ldflags
# Defaulting to full static build
GO_VARIABLE_PREFIX				= GO_VAR_
GO_VAR_BUILD_LABEL				:= $(BUILD_LABEL)
GO_LDFLAGS						= $(foreach v,$(filter $(GO_VARIABLE_PREFIX)%, $(.VARIABLES)),-X main.$(patsubst $(GO_VARIABLE_PREFIX)%,%,$(v)) $(value $(value v)))
GO_BUILD_FLAGS					= -a -tags netgo -installsuffix nocgo -ldflags "$(GO_LDFLAGS)"

# Ensure target path
dummy							:= $(shell test -d $(TARGET_PATH) || mkdir -p $(TARGET_PATH))

# Define targets

# default just build binary
default							: build

# target for debugging / printing variables
print-%							:
								@echo '$*=$($*)'

# build binary, tarball package, release container and rpm
all								: build tarball release-image rpm

# build binary object in container
# pass in exported vars and commandline vars for make to ensure environment
$(TARGET)/$(BUILD_OBJECT)		:
								docker run --rm --entrypoint /bin/sh $(BUILD_IMAGE_ENV_VARS) -v $(BUILD_IMAGE_CONTAINER_MOUNT) -v $(EXPORT_CONTAINER_MOUNT) -w $(BUILD_IMAGE_PROJECT_PATH) $(BUILD_IMAGE) -c "make restoredep $(MAKE_COMMANDLINE_VARS) && make go-install $(MAKE_COMMANDLINE_VARS) && cp $(BUILD_IMAGE_OBJECT_PATH) $(EXPORT_PATH)/$(BUILD_OBJECT)"

build							: $(TARGET)/$(BUILD_OBJECT)

docker-build-env				:
								docker run -i -t --rm --entrypoint /bin/sh -v $(BUILD_IMAGE_CONTAINER_MOUNT) -v $(EXPORT_CONTAINER_MOUNT) -w $(BUILD_IMAGE_PROJECT_PATH) $(BUILD_IMAGE) -c "/bin/bash"

# build tarball of binary object
tarball							: build
								mkdir $(TARGET)/$(TARBALL_FILENAME)
								cp $(TARGET)/$(TARBALL_OBJECTS) $(TARGET)/$(TARBALL_FILENAME)
								tar czf $(TARGET_PATH)/$(TARBALL_FILENAME).tar.gz -C $(TARGET_PATH) $(TARBALL_FILENAME) || (rm -f $(TARGET_PATH)/$(TARBALL_FILENAME).tar.gz; false)

# targets used for making the tar of objects for the release container
# expected to be done inside container
build-release-tar				: 
								tar cf $(EXPORT_PATH)/$(BUILD_RELEASE_TAR) $(BUILD_RELEASE_TAR_OBJECTS) || (rm -f $(EXPORT_PATH)/$(BUILD_RELEASE_TAR); false)

$(TARGET)/$(BUILD_RELEASE_TAR)  : $(TARGET)/$(BUILD_OBJECT)
								docker run --rm --entrypoint /bin/sh -v $(BUILD_IMAGE_CONTAINER_MOUNT) -v $(EXPORT_CONTAINER_MOUNT) -w $(BUILD_IMAGE_PROJECT_PATH) $(BUILD_IMAGE) -c "make build-release-tar"

# $(TARGET)/$(RELEASE_IMAGE_ID)   : $(TARGET)/$(BUILD_RELEASE_TAR)
#									(((docker build --force-rm -t $(RELEASE_IMAGE_REPOSITORY):$(RELEASE_IMAGE_TAG_UNIQUE) -f $(RELEASE_DOCKERFILE) .) && (docker inspect -f '{{.Id}}' $(RELEASE_IMAGE_REPOSITORY):$(RELEASE_IMAGE_TAG_UNIQUE) > $(TARGET_PATH)/$(RELEASE_IMAGE_ID))) || (rm -f $(TARGET_PATH)/$(RELEASE_IMAGE_ID); false))

# could have release-image depend upon the $(TARGET)/$(RELEASE_IMAGE_ID) instead to only generate release image as necessary
release-image					: build $(TARGET)/$(BUILD_RELEASE_TAR)
								docker build --force-rm -t $(RELEASE_IMAGE_REPOSITORY):$(RELEASE_IMAGE_TAG_UNIQUE) -f $(RELEASE_DOCKERFILE) .
								docker tag -f $(RELEASE_IMAGE_REPOSITORY):$(RELEASE_IMAGE_TAG_UNIQUE) $(RELEASE_IMAGE_REPOSITORY):$(RELEASE_IMAGE_TAG_NICE)
								docker tag -f $(RELEASE_IMAGE_REPOSITORY):$(RELEASE_IMAGE_TAG_UNIQUE) $(RELEASE_IMAGE_REPOSITORY):$(RELEASE_IMAGE_TAG_LATEST)


# either rely on $(RELEASE_IMAGE_ID) to ensure presence of image, or accept runtime error if image is not present
$(TARGET)/$(RELEASE_IMAGE_TAR)  : 
								docker save $(RELEASE_IMAGE_REPOSITORY):$(RELEASE_IMAGE_TAG_LATEST) > $(TARGET_PATH)/$(RELEASE_IMAGE_TAR) || (rm -f $(TARGET_PATH)/$(RELEASE_IMAGE_TAR); false)

# build rpm of project using project spec file
$(TARGET)/$(ARCH)/$(RPM)		: $(TARGET)/$(BUILD_OBJECT)
								docker run --rm --entrypoint /bin/sh -v $(RPMBUILD_IMAGE_SPECS_MOUNT) -v $(RPMBUILD_IMAGE_SOURCES_MOUNT) -v $(RPMBUILD_IMAGE_RPMS_MOUNT) -w $(RPMBUILD_IMAGE_RPMBUILD_PATH)/SPECS $(RPMBUILD_IMAGE) -c "RPM_BUILD=$(RPM_VERSION) RPM_REV=$(RPM_REVISION) RPM_REAL_NAME=$(RPM_REAL_NAME) RPM_SERVICE_NAME=$(RPM_SERVICE_NAME) RPM_BINARY_FILE=$(RPM_BINARY_FILE) rpmbuild -bb *.spec"

rpm								: $(TARGET)/$(ARCH)/$(RPM)

# convenience target for building rpmbuild image
rpmbuild-image					:
								docker build -t $(RPMBUILD_IMAGE) -f $(RPMBUILD_DOCKERFILE) .

# convenience target for pulling images locally
pull-images						:
								docker pull golang:1.4
								docker pull centos:centos6

clean							:
								-rm -rf $(TARGET_PATH)/*

# no need to do anything, version file generated every invocation of make
version							:
								@echo $(GENERATE_VERSION_INFO)

# save the release image to local disk
save							: $(TARGET)/$(RELEASE_IMAGE_TAR)

# push the release image to registry
push							: 
								docker push $(RELEASE_IMAGE_REPOSITORY):$(RELEASE_IMAGE_TAG_LATEST)

# targets for building go application
# recursively used inside the golang container
# can be used directly in development environments

# setup godep in environment
godep							:
								go get github.com/tools/godep

# update the godep dependency xml
savedep							: godep go-get go-install
								godep save $(GIT_REPOSITORY)/...

# restore the dependencies from godep
restoredep						: godep
								godep restore $(GIT_REPOSITORY)/...

# perform go get on project
# depend on generate to ensure preprocessing has occurred
go-get							: go-generate
								go get $(GIT_REPOSITORY)/...

go-generate						:
								go generate $(GIT_REPOSITORY)/...

# perform go build on project
go-build						: go-get
								go build $(GO_BUILD_FLAGS) $(GIT_REPOSITORY)/...

# perform go install on project
go-install						: go-get
								go install $(GO_BUILD_FLAGS) $(GIT_REPOSITORY)/...

.PHONY							: default all build tarball build-release-tar release-image rpm rpmbuild-image pull-images clean version save push godep savedep restoredep go-get go-generate go-build go-install docker-build-env
