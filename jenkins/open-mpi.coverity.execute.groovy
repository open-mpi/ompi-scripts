// -*- groovy -*-
//
// Build Coverity submission for Open MPI
//
//
// WORKSPACE Layout:
//   ompi-scripts/         ompi-scripts master checkout
//   coverity-tool/        Coverity tool build

import java.nio.charset.StandardCharsets

def snapshot_version = ""
def ompi_tarball_name = ""
def ompi_dir = ""
def ompi_version = ""
def coverity_path = ""

currentBuild.displayName = "#${currentBuild.number}"
currentBuild.description = "Coverity Nightly Build for Open MPI\n"

node("release-builder") {
    stage('Tools Checkout') {
        checkout(changelog: false, poll: false, scm: scm)
    }

    stage('Fetch Coverity Tool') {
        sh('mkdir -p ${WORKSPACE}/coverity-tool')
        s3Download(file:'coverity-tool/coverity_tools.tgz', bucket:'ompi-jenkins-config',
                   path: 'coverity/coverity_tools.tgz', force: true)
        sh('cd coverity-tool ; tar xf coverity_tools.tgz')
        def cov_bin
        cov_bin = sh(script: 'find ${WORKSPACE}/coverity-tool -name "cov-build" -print',
                     returnStdout: true).trim()
        coverity_path = sh(script: "dirname ${cov_bin}", returnStdout: true).trim()
        echo "path: ${coverity_path}"
    }

    stage('Fetch Open MPI') {
        sh('curl --fail -O https://download.open-mpi.org/nightly/open-mpi/main/latest_snapshot.txt')
        snapshot_version = sh(script: "cat latest_snapshot.txt", returnStdout: true).trim()

        currentBuild.displayName = "${currentBuild.displayName} - ${snapshot_version}"
        currentBuild.description = "${currentBuild.description} for version ${snapshot_version}"

        ompi_tarball_name = "openmpi-${snapshot_version}.tar.gz"
        sh("curl --fail -O https://download.open-mpi.org/nightly/open-mpi/main/${ompi_tarball_name}")
        sh("tar xf ${ompi_tarball_name}")

        def matcher = ("${ompi_tarball_name}" =~ /^openmpi-(.*)\.tar\..*/)
        if (matcher) {
            ompi_version = matcher[0][1]
	    ompi_dir="openmpi-${ompi_version}"
            echo "ompi_dir: ${ompi_dir}"
        } else{
            error "Cannot find ompi version and directory from ${ompi_tarball_name}"
        }
    }

    stage('Building PMIx') {
        sh("cd ${WORKSPACE}/${ompi_dir}/3rd-party/openpmix && ./configure --enable-debug --prefix=${WORKSPACE}/install && make -j 4 all && make install")
    }

    stage('Building Open MPI') {
        sh("cd ${WORKSPACE}/${ompi_dir} && ./configure --enable-debug --enable-mpi-fortran --enable-mpi-java --enable-oshmem --enable-oshmem-fortran --with-xpmem --with-libfabric=${HOME}/packages/libfabric --with-ucx=${HOME}/packages/ucx --with-pmix=${WORKSPACE}/install --without-prrte")
        withEnv(["PATH+EXTRA=${coverity_path}"]) {
            sh("cd ${WORKSPACE}/${ompi_dir} && cov-build --dir cov-int make")
        }
    }

    stage('Submit Results') {
        sh("cd ${WORKSPACE}/${ompi_dir} && tar jcf ${WORKSPACE}/submission.tar.bz2 cov-int")
        withCredentials([usernamePassword(credentialsId: 'b47cf375-6e78-4f1f-b215-18a7903a4763',
                                          passwordVariable: 'token',
                                          usernameVariable: 'project')]) {
            // This is a bit silly, but I can't find a sane way to have an sh script
            // string that both properly handles screts for the token field and
            // later does variable expansion.  So put the version in the
            // environment, since we can do environment expansion later.
	    def url_project=URLEncoder.encode(project, StandardCharsets.UTF_8.name())
	    echo "url_project: ${url_project}"
            withEnv(["ompi_version=${ompi_version}", "url_project=${url_project}"]) {
                sh('curl --form "token=$token" --form "email=jsquyres@cisco.com" --form "file=@${WORKSPACE}/submission.tar.bz2" --form "version=${ompi_version}"  --form "description=nightly-master" "https://scan.coverity.com/builds?project=${url_project}"')
            }
        }
    }

    stage('Cleanup') {
        sh("rm -rf ${WORKSPACE}/*")
    }
}
