// -*- groovy -*-
//
// Run a python script on a PR commit series to check
// for things like signed-off-by or commit emails.
//
//
// WORKSPACE Layout:
//   srcdir/               PR checking source tree
//   ompi-scripts/         ompi-scripts master checkout

def builder_label = "headnode"
def pr_context = env.context_name
def script_name = "ompi-scripts/" + env.script_name
def target_srcdir = "srcdir"

// Start by immediately tagging this as in progress...
setGitHubPullRequestStatus(context: pr_context, message: 'In progress', state: 'PENDING')

node(builder_label) {
  stage('Source Checkout') {
    try {
      checkout_code(target_srcdir);
    } catch (err) {
      setGitHubPullRequestStatus(context: pr_context,
                                 message: "Internal Accounting Error",
                                 state: 'ERROR')
      throw(err)
    }
  }

  stage('Checking git commits'){
    // There's no way to capture the stdout when the script fails,
    // so we have the script dump any output we want to use as the status
    // message in a file that is slurped up later.
    ret = sh(script: "python ${script_name} --status-msg-file checker-output.txt --gitdir ${target_srcdir} --base-branch origin/${env.GITHUB_PR_TARGET_BRANCH} --pr-branch origin/PR-${env.GITHUB_PR_NUMBER}",
             returnStatus: true)
    echo "script return code: ${ret}"

    // GitHub has three status states:
    //   SUCCESS - everything is good
    //   FAILURE - the tests functioned, but did not pass
    //   ERROR - the tests did not function
    // We expect script error code 0 to map to SUCCESS, 1 to map to
    // FAILURE, and all others map to error.  We do not expect to have
    // a useful status message on FAILURE.
    if (ret == 0 || ret == 1) {
      status_string = sh(script: "cat checker-output.txt", returnStdout: true)
      status_string = status_string.trim()
      if (ret == 0) {
        status_state = 'SUCCESS'
      } else {
        status_state = 'FAILURE'
      }
    } else {
      status_string = "Internal Accounting Error"
      status_state = 'ERROR'
    }

    setGitHubPullRequestStatus(context: pr_context,
                               message: "${status_string}",
                               state: "${status_state}")

    if (ret != 0) {
      currentBuild.result = 'FAILURE'
    }
  }
}


def checkout_code(target_srcdir) {
  pr_num = env.GITHUB_PR_NUMBER

  // Pull the refspecs for all the origin branches, as well as the PR
  // in question.  We could be more specific with origin branches, but
  // that would be more work for only a little space savings.
  checkout(changelog: false, poll: false,
           scm: [$class: 'GitSCM',
                  extensions: [[$class: 'RelativeTargetDirectory',
                               relativeTargetDir: "${target_srcdir}"]],
                 userRemoteConfigs: [[credentialsId: '6de58bf1-2619-4065-99bb-8d284b4691ce',
                                      refspec: "+refs/pull/${pr_num}/head:refs/remotes/origin/PR-${pr_num} +refs/heads/*:refs/remotes/origin/*",
                                      url: "${env.GITHUB_REPO_GIT_URL}"]]])

  // Make sure we have the ompi-scripts repository on the build node as well.
  // scm is a provided global variable that points to the repository
  // configured in the Jenkins job for the pipeline source.  Since the
  // pipeline and the helper scripts live in the same place, this is
  // perfect for us.  We check this out on the worker nodes so that
  // the helper scripts are always available.
  checkout(changelog: false, poll: false, scm: scm)
}
