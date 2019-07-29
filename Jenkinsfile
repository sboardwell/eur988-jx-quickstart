pipeline {
  agent {
      kubernetes {
          label "jenkins-nodejs"
          defaultContainer 'nodejs'
      }
  }
  environment {
    ORG                 = 'sboardwell'
    APP_NAME            = 'eur988-jx-quickstart'
    CHARTMUSEUM_CREDS   = credentials('jenkins-x-chartmuseum')
    GKE_SA              = credentials('gcr-push-key')
    DOCKER_REGISTRY     = 'us.gcr.io'
    DOCKER_REGISTRY_ORG = 'devops-project-200915'
  }

  stages {
    stage('Pre-check') {
      steps {
        script {
          processGitVersion()
          env.PREVIEW_VERSION = sh(returnStdout: true, script: "$WORKSPACE/scripts/version_util.sh f FullSemVer").trim().replace('+', '-')
          env.VERSION = env.PREVIEW_VERSION
          echo "VERSION: $VERSION and PREVIEW_VERSION: $PREVIEW_VERSION"
          addShortText text: "$VERSION"
        }
        sh "gcloud auth activate-service-account gcr-push@${DOCKER_REGISTRY_ORG}.iam.gserviceaccount.com --key-file ${GKE_SA}"
        sh "gcloud container images list-tags ${DOCKER_REGISTRY}/${DOCKER_REGISTRY_ORG}/${APP_NAME} | head -n 2"
        echo "Hello"
      }
    }
    stage('PR Builds') {
      when {
        changeRequest()
      }
      steps {

          sh 'export VERSION=$PREVIEW_VERSION && skaffold build -f skaffold.yaml'

          sh "jx step post build --image $DOCKER_REGISTRY/$DOCKER_REGISTRY_ORG/$APP_NAME:$PREVIEW_VERSION"
          dir('./charts/preview') {
              sh "make preview"
              sh "jx preview --app $APP_NAME --dir ../.. || helm delete --purge --no-hooks ${PREVIEW_NAMESPACE}"
          }
      }
    }
    stage('Release Builds') {
      when {
        anyOf {
            branch 'master'
            branch 'develop'
            branch 'release-*'
            branch 'hotfix-*'
        }
      }
      steps {

        // ensure we're not on a detached head
        sh "git checkout ${BRANCH_NAME}"

        dir('./charts/eur988-jx-quickstart') {
            sh "make tag"
        }

        sh 'skaffold build -f skaffold.yaml'

        sh "jx step post build --image $DOCKER_REGISTRY/$DOCKER_REGISTRY_ORG/$APP_NAME:$VERSION"

        // fetch the tags since the current checkout doesn't have them.
        dir ('./charts/eur988-jx-quickstart') {
            // release the helm chart
            sh 'jx step helm release'
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

def processGitVersion() {
  // Set git auths
  sh "git config --global credential.helper store"
  sh "jx step git credentials"

  // special case if (a) PR, (b) Merge commit
  // then we need to allow IGNORE_NORMALISATION_GIT_HEAD_MOVE = 1
  env.IGNORE_NORMALISATION_GIT_HEAD_MOVE = sh(
    returnStdout: true, 
    script: '''
      # if on a PR
      if git config --local --get-all remote.origin.fetch | grep -q refs\\/pull; then
        # if is merge commit
        if [ $(git show -s --pretty=%p HEAD | wc -w) -gt 1 ]; then 
          echo -n 1
        else
          echo -n 0
        fi
      else
        echo -n 0
      fi
    '''
  )

  // Determine the current checkout (branch vs merge commit with detached head)
  env.CHECKOUT_BACK_TO = sh(
    returnStdout: true, 
    script: 'git symbolic-ref HEAD &> /dev/null && echo -n $BRANCH_NAME || echo -n $(git rev-parse --verify HEAD)'
  )
    

  // Fetch CHANGE_TARGET and CHANGE_BRANCH if exists
  sh '[ -z $CHANGE_BRANCH ] || git fetch origin $CHANGE_BRANCH:$CHANGE_BRANCH'
  sh '[ -z $CHANGE_TARGET ] || git fetch origin $CHANGE_TARGET:$CHANGE_TARGET'

  // Fetch default default branches needed for gitversion
  // - these are the same as with the gitflow (master or stable, develop or dev, release-*)
  sh 'for b in $(git ls-remote --quiet --heads origin master develop release-* hotfix-* | sed "s:.*/::g"); do git fetch origin $b:$b; done'

  // Checkout aforementioned branches adding any previously existing branches to the EXISTING_BRANCHES file.
  sh '''
  touch EXISTING_BRANCHES
  for r in $(git branch -a | grep -E "remotes/origin/(master|develop|release-.*|hotfix-*|PR-.*)"); do
    echo "Remote branch: $r"
    rr="$(echo $r | cut -d/ -f 3)";
    {
      git checkout $rr 2>/dev/null && echo $rr >> EXISTING_BRANCHES || git checkout -f -b "$rr" $r
    }
  done
  cat EXISTING_BRANCHES
  '''

  // -------------------------------------------
  // Checkout the actual BRANCH_NAME under test.
  // -------------------------------------------
  // If you were to keep the detached head checked out you will see an error
  // similar to:
  //    "GitVersion has a bug, your HEAD has moved after repo normalisation."
  //
  // See: https://github.com/GitTools/GitVersion/issues/1627
  //
  // The version is not so relevant in a PR so we decided to just use the branch
  // under test.
  //sh "git checkout $BRANCH_NAME"
  sh "git checkout $CHECKOUT_BACK_TO"

  container('gitversion') {
      // 2 lines below are for debug purposes - uncomment if needed
      // sh 'dotnet /app/GitVersion.dll || true'
      // input 'wait'
      sh 'dotnet /app/GitVersion.dll'
      sh 'dotnet /app/GitVersion.dll > version.json'
  }

  // Checkout out original state
  sh "git checkout -f $CHECKOUT_BACK_TO"

  // Clean up - delete local branches checked out previously. leaving EXISTING_BRANCHES
  sh '''
    git branch | grep -v HEAD
    for r in $(git branch | grep -v $(git rev-parse --abbrev-ref HEAD)); do
      grep -E "^${r}$" EXISTING_BRANCHES && echo "Not deleting exsting branch '$r'." || git branch -D "$r"
    done
  '''

  // git reset hard to revert any changes
  sh 'git reset --hard'

  env.PREVIEW_NAMESPACE = sh(
          returnStdout: true,
          script: "echo \"jx-\$(git config --get remote.origin.url | sed -e 's|https://github.com/||' -e 's|.git\$||' -e 's|/|-|')-pr-${BRANCH_NAME.replaceAll('^(pr|PR)-', '')}\" | tr '[:upper:]' '[:lower:]'"
  ).trim()
  echo "My preview ns will be: ${PREVIEW_NAMESPACE}"

}
