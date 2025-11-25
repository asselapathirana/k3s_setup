grafana:
  admin:
    existingSecret: grafana-admin
    userKey: admin-user
    passwordKey: admin-password
  service:
    type: ClusterIP
  ingress:
    enabled: true
    className: nginx
    hosts:
      - grafana.${DOMAIN_NAME}
    tls:
      - secretName: grafana-tls-secret
        hosts:
          - grafana.${DOMAIN_NAME}

prometheus:
  prometheusSpec:
    retention: 15d
    resources:
      requests:
        memory: "512Mi"
        cpu: "200m"
      limits:
        memory: "2Gi"
        cpu: "1"
  ingress:
    enabled: false

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "300m"
