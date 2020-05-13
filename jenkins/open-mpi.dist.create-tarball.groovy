// -*- groovy -*-
//
// Build an Open MPI dist release
//
//
// WORKSPACE Layout:
//   dist-files/           Output of build
//   autotools-install/    Autotools install for the builder
//   ompi/                 Open MPI source tree
//   ompi-scripts/         ompi-scripts master checkout
//   rpmbuild/             Where RPMs go to die...

import java.text.SimpleDateFormat

def rpm_builder = 'amazon_linux_2'
def manpage_builder = 'ubuntu_18.04'

def release_version
def branch
def tarball
def srpm_name
def s3_prefix
def download_prefix
def build_type = env.Build_type.toLowerCase()
def dateFormat = new SimpleDateFormat("MM/dd/yyyy HH:mm")
def date = new Date()
def build_date = dateFormat.format(date)

currentBuild.displayName = "#${currentBuild.number} - ${build_type} - ${env.REF}"
currentBuild.description = "<b>Build type:</b> ${build_type}<br>\n<b>Ref:</b> ${env.REF}<br>\n<b>Build date:</b> ${build_date}<br>\n"

// Step 1: Build a release tarball and RPM.  Needs to be on an
// RPM-based system, and easier to do it all in serial on one node.
node(rpm_builder) {
  stage('Source Checkout') {
    checkout_code();
  }

  stage('Installing Dependencies') {
    // because we build tags or hashes, not just branch heads,
    // there's not a great way to do the branch -> Autotools
    // version matching.  So instead grab them from the
    // make_dist_tarball script
    sh '/bin/bash ompi-scripts/jenkins/open-mpi-autotools-build.sh ompi'
  }

  // Build the initial tarball, verify that the resulting tarball
  // has a version that matches the tag if we're building Release or
  // Pre-Release tarballs.  Scratch tarballs have a much looser
  // requirement, because scratch.
  stage('Build Tarball') {
    withEnv(["PATH+AUTOTOOLS=${WORKSPACE}/autotools-install/bin",
	     "LD_LIBRARY_PATH+AUTOTOOLS=${WORKSPACE}/autotools-install/lib"]) {
      def greek_option = ""
      switch (build_type) {
      case "release":
        greek_option = "--no-greek"
	s3_prefix="s3://open-mpi-release/release"
	download_prefix="https://download.open-mpi.org/release"
	break
      case "pre-release":
        greek_option = "--greekonly"
	s3_prefix="s3://open-mpi-release/release"
	download_prefix="https://download.open-mpi.org/release"
	break
      case "scratch":
        greek_option = "--greekonly"
	def uuid = UUID.randomUUID().toString()
	s3_prefix="s3://open-mpi-scratch/scratch/${uuid}"
	download_prefix="https://download.open-mpi.org/scratch/${uuid}"
	break
      default:
        error("Unknown build type ${env.Build_type}")
	break
      }

      sh "/bin/bash ompi-scripts/jenkins/open-mpi.dist.create-tarball.build-tarball.sh ${build_type} ${env.REF} ${s3_prefix} \"${build_date}\""

      // if we just call File to read the file, it will look on
      // master's filesystem, instead of on this node.  So use
      // a shell instead.
      tarball = sh(script: "cat build-tarball-filename.txt",
		   returnStdout: true).trim()
      branch = sh(script: "cat build-tarball-branch_directory.txt",
		  returnStdout: true).trim()
      build_prefix="${s3_prefix}/open-mpi/${branch}"
      download_prefix="${download_prefix}/open-mpi/${branch}"
      currentBuild.description="${currentBuild.description}<b>Tarball:</b> <A HREF=\"${download_prefix}/${tarball}\">${download_prefix}/${tarball}</A><BR>\n"
    }
  }

  stage('Build Source RPM') {
    prep_rpm_environment()
    sh "/bin/bash ompi-scripts/jenkins/open-mpi.dist.create-tarball.build-srpm.sh ${s3_prefix} ${tarball} ${branch} \"${build_date}\""
    srpm_name = sh(returnStdout:true, script: 'cat ${WORKSPACE}/srpm-name.txt').trim()
    currentBuild.description="${currentBuild.description}<b>SRC RPM:</b> <A HREF=\"${download_prefix}/${srpm_name}\">${download_prefix}/${srpm_name}</A><BR>\n"
  }
}

// Run a bunch of different tests in parallel
parallel (
  "man pages" : {
    node(manpage_builder) {
      stage('Build Man Pages') {
	checkout_code();
	sh "ls -lR . ; /bin/bash ompi-scripts/jenkins/open-mpi.dist.create-tarball.build-manpages.sh ${build_prefix} ${tarball} ${branch}"
	artifacts = sh(returnStdout:true, script:'cat ${WORKSPACE}/manpage-build-artifacts.txt').trim()
	currentBuild.description="${currentBuild.description}<b>Manpages:</b> <A HREF=\"${artifacts}\">${artifacts}</A><BR>\n"
      }
    }
  },

  "tarball distcheck" : {
    node(rpm_builder) {
      stage('Tarball Distcheck') {
	remove_build_directory('openmpi-*')
	sh """aws s3 cp ${build_prefix}/${tarball} ${tarball}
tar xf ${tarball}
cd openmpi-*
./configure
make distcheck"""
      }
    }
  },

  "rpm test suites" : {
    node(rpm_builder) {
      stage('RPM Build') {
	prep_rpm_environment()
	sh """aws s3 cp ${build_prefix}/${srpm_name} ${srpm_name}
rpmbuild --rebuild ${srpm_name}
bin_rpm_name=`find ${WORKSPACE}/rpmbuild/RPMS -name "*.rpm" -print`
sudo rpm -Uvh \${bin_rpm_name}"""
      }
    }
  },

  "tarball test suites" : {
    node('gcc5') {
      stage('Tarball Test Build') {
	remove_build_directory('openmpi-*')
	sh """aws s3 cp ${build_prefix}/${tarball} ${tarball}
tar xf ${tarball}
cd openmpi-*
./configure --prefix=$WORKSPACE/openmpi-install
make -j 8 all
make check
make install"""
      }
    }
  }
)


def prep_rpm_environment() {
  sh """rm -rf ${WORKSPACE}/rpmbuild ; mkdir -p ${WORKSPACE}/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS} ; rm -f ~/.rpmmacros ; echo \"%_topdir ${WORKSPACE}/rpmbuild\" > ~/.rpmmacros"""
}


// delete build directory (relative to WORKSPACE), dealing with the autotools silly permissions
def remove_build_directory(dirname) {
  sh """if ls -1 ${dirname} ; then
    chmod -R u+w ${dirname}
    rm -rf ${dirname}
fi"""
}


def checkout_code() {
  checkout(changelog: false, poll: false,
	   scm: [$class: 'GitSCM', branches: [[name: '$REF']],
		 doGenerateSubmoduleConfigurations: false,
		 extensions: [[$class: 'WipeWorkspace'],
			      [$class: 'RelativeTargetDirectory',
			       relativeTargetDir: 'ompi']],
		 submoduleCfg: [],
		 userRemoteConfigs: [[credentialsId: '6de58bf1-2619-4065-99bb-8d284b4691ce',
				      url: 'https://github.com/open-mpi/ompi/']]])
  // scm is a provided global variable that points to the repository
  // configured in the Jenkins job for the pipeline source.  Since the
  // pipeline and the helper scripts live in the same place, this is
  // perfect for us.  We check this out on the worker nodes so that
  // the helper scripts are always available.
  checkout(changelog: false, poll: false, scm: scm)
}
