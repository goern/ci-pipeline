#!/bin/bash
set -eux

CURRENTDIR=$(pwd)
if [ ${CURRENTDIR} == "/" ] ; then
    cd /home
    CURRENTDIR=/home
fi
export TEST_SUBJECTS=${CURRENTDIR}/untested-atomic.qcow2
export TEST_ARTIFACTS=${CURRENTDIR}/logs
# The test artifacts must be an empty directory
rm -rf ${TEST_ARTIFACTS}
mkdir -p ${TEST_ARTIFACTS}

# Invoke tests according to section 1.7.2 here:
# https://fedoraproject.org/wiki/Changes/InvokingTests

if [ -z "${package:-}" ]; then
	if [ $# -lt 1 ]; then
		echo "No package defined"
		exit 2
	else
		package="$1"
	fi
fi

# Replace beakerlib role with one that won't choke installing restraint while on a rawhide distro
cp -f /tmp/beakerlib-role-main.yml /etc/ansible/roles/standard-test-beakerlib/tasks/main.yml

# Make sure we have or have downloaded the test subject
if [ -z "${TEST_SUBJECTS:-}" ]; then
	echo "No subject defined"
	exit 2
elif ! file ${TEST_SUBJECTS:-}; then
	wget -q -O testimage.qcow2 ${TEST_SUBJECTS}
	export TEST_SUBJECTS=${PWD}/testimage.qcow2
fi

# Check out the upstreamfirst repository for this package
rm -rf ${package}
if ! git clone https://upstreamfirst.fedorainfracloud.org/${package}; then
	echo "No upstreamfirst repo for this package! Exiting..."
	exit 0
fi

# The specification requires us to invoke the tests in the checkout directory
pushd ${package}

function clean_up {
     rm -rf tests/package
     mkdir -p tests/package
     cp ${TEST_ARTIFACTS}/* tests/package/
}
trap clean_up EXIT SIGHUP SIGINT SIGTERM

# The inventory must be from the test if present (file or directory) or defaults
if [ -e inventory ] ; then
    ANSIBLE_INVENTORY=$(pwd)/inventory
    export ANSIBLE_INVENTORY
fi

# Invoke each playbook according to the specification
for playbook in tests*.yml; do
	if [ -f ${playbook} ]; then
		ansible-playbook --inventory=$ANSIBLE_INVENTORY \
                        --extra-vars "ansible_python_interpreter=/usr/bin/python3" \
			--extra-vars "subjects=$TEST_SUBJECTS" \
			--extra-vars "artifacts=$TEST_ARTIFACTS" \
			--tags classic ${playbook}
	fi
done
popd
popd
