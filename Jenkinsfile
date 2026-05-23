pipeline {
    agent {
        kubernetes {
            inheritFrom 'deploy-sec-base-builder'
        }
    }

    environment {
        IMAGE = 'harbor.tuxgrid.com/platform/build-base'
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    triggers {
        pollSCM('H/5 * * * *')
    }

    stages {
        stage('Build') {
            steps {
                container('kaniko') {
                    withCredentials([usernamePassword(
                            credentialsId: 'harbor-robot-platform',
                            usernameVariable: 'HARBOR_USER',
                            passwordVariable: 'HARBOR_PASS')]) {
                        sh '''
                            mkdir -p /kaniko/.docker
                            AUTH=$(printf '%s:%s' "${HARBOR_USER}" "${HARBOR_PASS}" | base64 | tr -d '\n')
                            printf '{"auths":{"harbor.tuxgrid.com":{"auth":"%s"}}}' "${AUTH}" \
                                > /kaniko/.docker/config.json
                            PLATFORM_CA_B64=$(base64 -w0 /mitm-data/ca.pem 2>/dev/null || true)
                            /kaniko/executor \
                                --context=dir://. \
                                --dockerfile=Dockerfile \
                                --build-arg "PLATFORM_CA_B64=${PLATFORM_CA_B64}" \
                                --build-arg HTTPS_PROXY=http://127.0.0.1:8080 \
                                --build-arg HTTP_PROXY=http://127.0.0.1:8080 \
                                --destination=${IMAGE}:${GIT_COMMIT:0:7} \
                                --digest-file=${WORKSPACE}/image.digest \
                                --snapshot-mode=redo \
                                --compressed-caching=false \
                                --cache=true \
                                --cache-repo=harbor.tuxgrid.com/platform/cache/build-base
                        '''
                    }
                }
            }
        }

        stage('Archive') {
            steps {
                script {
                    env.IMAGE_DIGEST = readFile("${WORKSPACE}/image.digest").trim()
                    writeJSON file: 'artifacts.json', json: [
                        builds: [[tag: "${env.IMAGE}@${env.IMAGE_DIGEST}", number: env.BUILD_NUMBER]]
                    ]
                    archiveArtifacts artifacts: 'artifacts.json', fingerprint: true
                }
            }
        }

        stage('Sign') {
            steps {
                container('cosign') {
                    withCredentials([
                        string(credentialsId: 'cosign-key', variable: 'COSIGN_PRIVATE_KEY'),
                        usernamePassword(
                            credentialsId: 'harbor-robot-platform',
                            usernameVariable: 'HARBOR_USER',
                            passwordVariable: 'HARBOR_PASS'),
                    ]) {
                        sh '''
                            printf '%s' "${COSIGN_PRIVATE_KEY}" > /tmp/cosign.key
                            chmod 600 /tmp/cosign.key
                            AUTH=$(printf '%s:%s' "${HARBOR_USER}" "${HARBOR_PASS}" | base64 | tr -d '\n')
                            mkdir -p ~/.docker
                            printf '{"auths":{"harbor.tuxgrid.com":{"auth":"%s"}}}' "${AUTH}" \
                                > ~/.docker/config.json
                            COSIGN_PASSWORD="" cosign sign --key /tmp/cosign.key --yes \
                                --tlog-upload=false \
                                "${IMAGE}@${IMAGE_DIGEST}"
                            rm -f /tmp/cosign.key ~/.docker/config.json
                        '''
                    }
                }
            }
        }

        stage('Provenance') {
            steps {
                container('cosign') {
                    withCredentials([
                        string(credentialsId: 'cosign-key', variable: 'COSIGN_PRIVATE_KEY'),
                        usernamePassword(
                            credentialsId: 'harbor-robot-platform',
                            usernameVariable: 'HARBOR_USER',
                            passwordVariable: 'HARBOR_PASS'),
                    ]) {
                        sh '''
                            printf '%s' "${COSIGN_PRIVATE_KEY}" > /tmp/cosign.key
                            chmod 600 /tmp/cosign.key
                            AUTH=$(printf '%s:%s' "${HARBOR_USER}" "${HARBOR_PASS}" | base64 | tr -d '\n')
                            mkdir -p ~/.docker
                            printf '{"auths":{"harbor.tuxgrid.com":{"auth":"%s"}}}' "${AUTH}" \
                                > ~/.docker/config.json

                            if command -v python3 >/dev/null 2>&1; then
                                python3 - << 'PYEOF'
import json, os, datetime

deps = []
if os.path.exists("/mitm-data/deps.ndjson"):
    with open("/mitm-data/deps.ndjson") as f:
        for line in f:
            try:
                e = json.loads(line.strip())
                if e.get("status", 0) < 400 and e.get("url"):
                    dep = {"uri": e["url"]}
                    if e.get("sha256"):
                        dep["digest"] = {"sha256": e["sha256"]}
                    deps.append(dep)
            except Exception:
                pass

git_commit = os.environ.get("GIT_COMMIT", "")
git_url = os.environ.get("GIT_URL", "")
if git_commit:
    deps.insert(0, {"uri": git_url, "digest": {"gitCommit": git_commit}})

now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
ts_ms = os.environ.get("BUILD_TIMESTAMP", "")
started = datetime.datetime.utcfromtimestamp(int(ts_ms) / 1000).strftime("%Y-%m-%dT%H:%M:%SZ") if ts_ms else now
provenance = {
    "buildDefinition": {
        "buildType": "https://tuxgrid.com/buildType/jenkins-kaniko/v1",
        "externalParameters": {
            "ref": os.environ.get("GIT_COMMIT", ""),
            "repository": os.environ.get("GIT_URL", ""),
            "dockerfile": "Dockerfile",
        },
        "resolvedDependencies": deps,
    },
    "runDetails": {
        "builder": {"id": "https://jenkins.tuxgrid.com/job/" + os.environ.get("JOB_NAME", "") + "/" + os.environ.get("BUILD_NUMBER", "")},
        "metadata": {
            "invocationId": os.environ.get("BUILD_URL", ""),
            "startedOn": started,
            "finishedOn": now,
        },
    },
}
with open("/tmp/provenance.json", "w") as f:
    json.dump(provenance, f, indent=2)
print("provenance.json: {} resolved dependencies".format(len(deps)))
PYEOF
                            else
                                echo "python3 not found, using simple provenance (no deps.ndjson)"
                                NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
                                STARTED=$(date -u -d "@$((BUILD_TIMESTAMP / 1000))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "${NOW}")
                                cat > /tmp/provenance.json << PROVEOF
{
  "buildDefinition": {
    "buildType": "https://tuxgrid.com/buildType/jenkins-kaniko/v1",
    "externalParameters": {
      "ref": "${GIT_COMMIT}",
      "repository": "${GIT_URL}",
      "dockerfile": "Dockerfile"
    },
    "resolvedDependencies": [
      {"uri": "${GIT_URL}", "digest": {"gitCommit": "${GIT_COMMIT}"}}
    ]
  },
  "runDetails": {
    "builder": {"id": "https://jenkins.tuxgrid.com/job/${JOB_NAME}/${BUILD_NUMBER}"},
    "metadata": {
      "invocationId": "${BUILD_URL}",
      "startedOn": "${STARTED}",
      "finishedOn": "${NOW}"
    }
  }
}
PROVEOF
                            fi

                            COSIGN_PASSWORD="" cosign attest --key /tmp/cosign.key --yes \
                                --tlog-upload=false \
                                --type slsaprovenance1 \
                                --predicate /tmp/provenance.json \
                                "${IMAGE}@${IMAGE_DIGEST}"

                            if command -v syft >/dev/null 2>&1; then
                                SYFT_CHECK_FOR_APP_UPDATE=false syft "${IMAGE}@${IMAGE_DIGEST}" \
                                    --output cyclonedx-json=/tmp/sbom.json

                                COSIGN_PASSWORD="" cosign attest --key /tmp/cosign.key --yes \
                                    --tlog-upload=false \
                                    --type cyclonedx \
                                    --predicate /tmp/sbom.json \
                                    "${IMAGE}@${IMAGE_DIGEST}"

                                rm -f /tmp/sbom.json
                            else
                                echo "syft not found, skipping SBOM attestation"
                            fi

                            rm -f /tmp/cosign.key ~/.docker/config.json /tmp/provenance.json
                        '''
                    }
                }
            }
        }

        stage('Promote') { steps { script { platformPromote() } } }
    }
}
