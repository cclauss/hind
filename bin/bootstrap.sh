#!/bin/zsh -u


echo      "name = \"$(hostname -s)\"" >> $NOMAD_HCL
echo "node_name = \"$(hostname -s)\"" >> $CONSUL_HCL


if [ $FIRST ]; then
  # setup for 2+ VMs to have their nomad and consul daemons be able to talk to each other
  export FIRSTIP=$(host $FIRST | perl -ane 'print $F[3] if $F[2] eq "address"' | head -1)

  echo "encrypt = \"$TOK_C\""        >> $CONSUL_HCL
  echo "retry_join = [\"$FIRSTIP\"]" >> $CONSUL_HCL

  echo "server { encrypt = \"$TOK_N\" }"               >> $NOMAD_HCL
  echo "server_join { retry_join = [ \"$FIRSTIP\" ] }" >> $NOMAD_HCL
  echo "server { bootstrap_expect = 2 }"               >> $NOMAD_HCL
else
  echo 'bootstrap_expect = 1' >> $CONSUL_HCL
fi



# fire up daemons
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf



if [ ! $FIRST ]; then

  touch /tmp/bootstrap
  # try up to ~10m to bootstrap nomad
  for try in $(seq 0 600)
  do
    TOK_C=$(consul keygen | tr -d ^)
    TOK_N=$(nomad operator gossip keyring generate | tr -d ^)
    nomad acl bootstrap 2>/tmp/boot.log >> /tmp/bootstrap

    [ "$?" = "0" ] && break
    ( fgrep 'ACL bootstrap already done' /tmp/boot.log ) && break
    sleep 1
  done

  # setup for 2+ VMs to have their nomad and consul daemons be able to talk to each other
  echo "encrypt = \"$TOK_C\"" >> $CONSUL_HCL
  echo "server { encrypt = \"$TOK_N\" }" >> $NOMAD_HCL

  echo export NOMAD_TOKEN=$(fgrep 'Secret ID' /tmp/bootstrap |cut -f2- -d= |tr -d ' ') > $CONFIG
  rm -f /tmp/bootstrap

  source $CONFIG

else

  # try up to ~5m for consul to be up and happy
  for try in $(seq 0 150)
  do
    sleep 2
    consul members 2>>/tmp/boot.log >>/tmp/boot.log
    [ "$?" = "0" ] && break
  done

  touch $CONFIG
fi


if [ $HOST_UNAME = Darwin ]; then
  echo "export NOMAD_ADDR=http://$FQDN:6000" >> $CONFIG
else
  echo "export NOMAD_ADDR=https://$FQDN"     >> $CONFIG
fi


chmod 400 $CONFIG



if [ $NFSHOME ]; then
  echo '
client {
  host_volume "home-ro" {
    path      = "/home"
    read_only = true
  }

  host_volume "home-rw" {
    path      = "/home"
    read_only = false
  }
}' >> $NOMAD_HCL
fi


FI=/lib/systemd/system/systemd-networkd.socket
if [ -e $FI ]; then
  # workaround focal-era bug after ~70 deploys (and thus 70 "veth" interfaces)
  # https://www.mail-archive.com/ubuntu-bugs@lists.ubuntu.com/msg5888501.html
  sed -i -e 's^ReceiveBuffer=.*$^ReceiveBuffer=256M^' $FI
fi


# verify nomad & consul accessible & working
echo
echo
consul members
echo
nomad server members
echo
