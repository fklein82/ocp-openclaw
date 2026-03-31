# Contributing to OpenClaw on OpenShift

Thank you for your interest in contributing to this project! 🎉

## 🤝 How to Contribute

### Reporting Issues

If you find a bug or have a feature request:

1. Check if the issue already exists in [GitHub Issues](https://github.com/fklein82/ocp-openclaw/issues)
2. If not, create a new issue with:
   - Clear title and description
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - Your environment (OpenShift version, cluster type, etc.)
   - Relevant logs or screenshots

### Submitting Changes

1. **Fork the repository**
   ```bash
   gh repo fork fklein82/ocp-openclaw --clone
   cd ocp-openclaw
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow the existing code style
   - Update documentation as needed
   - Test your changes on a real OpenShift cluster

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "Brief description of your changes"
   ```

5. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Create a Pull Request**
   - Go to the original repository
   - Click "New Pull Request"
   - Select your fork and branch
   - Describe your changes clearly

## 📝 Contribution Guidelines

### Code Style

- Use clear, descriptive variable names
- Add comments for complex logic
- Follow YAML best practices for manifests
- Use shellcheck for bash scripts

### Documentation

- Update README.md if adding new features
- Document configuration options
- Add examples where helpful
- Update relevant docs/ files

### Testing

Before submitting a PR, please:

1. Test on a real OpenShift cluster
2. Verify the deployment with:
   ```bash
   make validate
   ./scripts/validate.sh
   ```
3. Check that all scripts are executable
4. Ensure no secrets are committed

### Commit Messages

Use clear, descriptive commit messages:

```
Brief summary (50 chars or less)

More detailed explanation if needed:
- What changed
- Why it changed
- Any breaking changes or migration notes
```

## 🎯 Areas for Contribution

We welcome contributions in these areas:

### High Priority

- [ ] Support for additional OpenShift versions (4.12, 4.13, etc.)
- [ ] Helm chart alternative to Kustomize
- [ ] Monitoring and alerting setup (Prometheus/Grafana)
- [ ] Multi-replica deployment support
- [ ] Automated backup/restore procedures

### Medium Priority

- [ ] GitOps enhancements (Argo CD examples)
- [ ] Additional security hardening
- [ ] Performance tuning guides
- [ ] CI/CD pipeline examples
- [ ] Integration tests

### Nice to Have

- [ ] Support for other cloud providers (Azure ARO, GCP)
- [ ] Custom metrics and dashboards
- [ ] Cost optimization tips
- [ ] Disaster recovery procedures
- [ ] Migration guides

## 🧪 Testing Your Changes

### Local Testing

```bash
# Validate manifests
make build-manifests ENV=lab

# Test installation (dry-run)
oc apply -k manifests/lab --dry-run=client

# Full deployment test
make deploy-lab
make validate
```

### Cleanup

```bash
make uninstall
```

## 📚 Resources

- [OpenShift Documentation](https://docs.openshift.com)
- [OpenClaw Documentation](https://docs.openclaw.ai)
- [Kustomize Documentation](https://kustomize.io)

## 🐛 Found a Security Issue?

Please **do not** open a public issue. Instead:

1. Email the maintainers directly
2. Include "SECURITY" in the subject line
3. Provide details about the vulnerability
4. Allow time for a fix before public disclosure

## 💬 Questions?

- Open a [Discussion](https://github.com/fklein82/ocp-openclaw/discussions)
- Check existing [Issues](https://github.com/fklein82/ocp-openclaw/issues)
- Review the [documentation](docs/)

## 📄 License

By contributing to this project, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).

---

Thank you for making this project better! 🙏
