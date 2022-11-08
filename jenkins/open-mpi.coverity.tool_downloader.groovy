// -*- groovy -*-
//
// Download the latest Coverity scan-build toolset from Coverity and put in S3
//

node('headnode') {
  stage('Download From Coverity') {
    withCredentials([usernamePassword(credentialsId: 'b47cf375-6e78-4f1f-b215-18a7903a4763',
                                      passwordVariable: 'token',
                                      usernameVariable: 'project')]) {
      sh(label: 'Download via curl', script: '''
        curl --fail -d "token=$token&project=$project" https://scan.coverity.com/download/cxx/linux64 --output linux64.tar.gz''')
    }
  }
  stage('Upload to S3') {
    s3Upload acl: 'Private', bucket: 'ompi-jenkins-config', file: 'linux64.tar.gz', path: 'coverity/coverity_tools.tgz'
  }
}
