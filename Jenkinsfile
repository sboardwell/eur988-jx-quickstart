pipeline {
  agent {
      kubernetes {
          label "jenkins-nodejs"
          defaultContainer 'nodejs'
      }
  }
  environment {
    ORG = 'sboardwell'
    APP_NAME = 'eur988-jx-quickstart'
    CHARTMUSEUM_CREDS = credentials('jenkins-x-chartmuseum')
    DOCKER_REGISTRY_ORG = 'sboardwell'
  }
  stages {
    stage('Pre-check') {
      steps {
        script {

          sh "git config --global credential.helper store"
          sh "jx step git credentials"
          sh "git branch -a"

          env.ACTUAL_MERGE_HASH = sh(returnStdout: true, script: "git rev-parse --verify HEAD").trim()
          env.CHECKOUT_BACK_TO = sh(returnStdout: true, script: 'git symbolic-ref HEAD &> /dev/null && echo -n $BRANCH_NAME || echo -n $ACTUAL_MERGE_HASH')

          // fetch CHANGE_TARGET if exists
          sh '[ -z $CHANGE_TARGET ] || git fetch origin $CHANGE_TARGET:$CHANGE_TARGET'
          sh '''
          for r in $(git branch -a | grep "remotes/origin" | grep -v "remotes/origin/HEAD"); do
            echo "Remote branch: $r"
            rr="$(echo $r | cut -d/ -f 3)";
            {
              git checkout $rr 2>/dev/null && echo $rr >> EXISTING_BRANCHES || git checkout -f -b "$rr" $r
            }
          done

          touch EXISTING_BRANCHES && cat EXISTING_BRANCHES
          '''

          sh "git branch -a"
          sh "git checkout $BRANCH_NAME"

          container('gitversion') {
              sh 'pwd'
              sh 'ls -al'
              sh 'env'
              sh 'dotnet /app/GitVersion.dll || true'
              //input 'wait'
              sh 'dotnet /app/GitVersion.dll'
              sh 'dotnet /app/GitVersion.dll > version.json'
          }

          sh "git checkout -f $CHECKOUT_BACK_TO"

          // delete checked out local branches
          sh '''
            for r in $(git branch | grep -v "HEAD"); do
              grep -E "^${r}$" EXISTING_BRANCHES && echo "Not deleting exsting branch '$r'." || git branch -d "$r"
            done

            git reset --hard
          '''

          env.PREVIEW_VERSION = sh(returnStdout: true, script: "$WORKSPACE/scripts/version_util.sh f FullSemVer").trim().replace('+', '-')
          env.VERSION = env.PREVIEW_VERSION
          echo "VERSION: $VERSION and PREVIEW_VERSION: $PREVIEW_VERSION"
          addShortText text: "$VERSION"
        }
      }
    }
  }
  post {
        always {
          cleanWs()
        }
  }
}


