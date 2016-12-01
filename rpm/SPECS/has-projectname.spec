%define real_name       %(echo "RPM_REAL_NAME")
%define rpm_version     %(echo "$RPM_BUILD")
%define rpm_rev         %(echo "$RPM_REV")
%define build_date      %(echo `date`)
%define service         %(echo "$RPM_SERVICE_NAME")
%define binary_file     %(echo "$RPM_BINARY_FILE")

Summary:       Generic binary service
Name:          has-%{service}
Version:       %{rpm_version}
Release:       %{rpm_rev}
License:       HasOffers
Group:         System Environment/Daemons
Source0: %{binary_file}

%description
Generic binary service

%prep
%build
%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/var/has/%{service}/bin/
cp -p %{SOURCE0} %{buildroot}/var/has/%{service}/bin/.

%post
echo "Install: `date`"                                       >> /var/has/%{service}/has-%{service}.history
echo "--------"                                              >> /var/has/%{service}/has-%{service}.history

%files
%defattr(0644,root,root,0755)
%dir /var/has/%{service}
/var/has/%{service}/*
%attr(0755,root,root) /var/has/%{service}/bin/%{binary_file}

%changelog
* Fri Mar 20 2015 Michael Hoglan <michaelh@tune.com>
- 20150320-1 - Initial spec file for service
