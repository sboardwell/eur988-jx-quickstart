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
          input "wait wait wait"

          sh "git config --global credential.helper store"
          sh "jx step git credentials"
          sh "git branch -a"

          env.ACTUAL_MERGE_HASH = sh(returnStdout: true, script: "git rev-parse --verify HEAD").trim()

          sh '''
          for r in $(git branch -a | grep "remotes/origin" | grep -v "remotes/origin/HEAD"); do
            echo "Remote branch: $r"
            rr="$(echo $r | cut -d/ -f 3)";
            {
              git checkout $rr 2>/dev/null && echo $rr >> EXISTING_BRANCHES || git checkout -f -b "$rr" $r
            }
          done

          cat EXISTING_BRANCHES
          '''

          sh "git branch -a"
          sh "git checkout $BRANCH_NAME"

          container('gitversion') {
              sh 'dotnet /app/GitVersion.dll'
              sh 'dotnet /app/GitVersion.dll > version.json'
          }

          sh "git checkout -f $ACTUAL_MERGE_HASH"

          // delete checked out local branches
          sh '''
            for r in $(git branch | grep -v "HEAD"); do
              git branch -d "$r"
            done

            git reset --hard
          '''

          env.PREVIEW_VERSION = sh(returnStdout: true, script: "$WORKSPACE/scripts/version_util.sh f FullSemVer").trim().replace('+', '-')
          env.VERSION = env.PREVIEW_VERSION
        }
      }
    }

    stage('CI Build and push snapshot') {
      when {
        branch 'PR-*'
      }
      environment {
        PREVIEW_NAMESPACE = "$APP_NAME-$BRANCH_NAME".toLowerCase()
        HELM_RELEASE = "$PREVIEW_NAMESPACE".toLowerCase()
      }
      steps {
        container('nodejs') {
          sh "jx step pr labels -b --pr ${BRANCH_NAME.replaceAll('^(pr|PR)-', '')}"
          sh "npm install"
          sh "CI=true DISPLAY=:99 npm test"
          sh "export VERSION=$PREVIEW_VERSION && skaffold build -f skaffold.yaml"
          sh "jx step post build --image $DOCKER_REGISTRY/$ORG/$APP_NAME:$PREVIEW_VERSION"
          dir('./charts/preview') {
            sh "make preview"
            sh "jx preview --app $APP_NAME --dir ../.."
          }
        }
      }
    }
    stage('Build Release') {
      when {
        branch 'master'
      }
      steps {
        container('nodejs') {

          // ensure we're not on a detached head
          sh "git checkout master"
          sh "git config --global credential.helper store"
          sh "jx step git credentials"

          // so we can retrieve the version in later steps
          sh "jx step tag --version $VERSION"
        }

        container('nodejs') {
          sh "npm install"
          sh "CI=true DISPLAY=:99 npm test"
          sh "export VERSION=$VERSION && skaffold build -f skaffold.yaml"
          sh "jx step post build --image $DOCKER_REGISTRY/$ORG/$APP_NAME:\$(cat VERSION)"
        }
      }
    }
    stage('Promote to Environments') {
      when {
        branch 'master'
      }
      steps {
        container('nodejs') {
          dir('./charts/eur988-jx-quickstart') {
            sh "jx step changelog --batch-mode --version v$VERSION"

            // release the helm chart
            sh "jx step helm release"

            // promote through all 'Auto' promotion Environments
            sh "jx promote -b --all-auto --timeout 1h --version $VERSION"
          }
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

