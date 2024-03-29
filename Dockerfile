FROM zephyrprojectrtos/zephyr-build:v0.13.1

RUN sudo apt update
RUN sudo apt install -y curl openssh-client less xxd
RUN sudo apt install -y llvm gawk
RUN sudo pip3 uninstall -y west

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

COPY ./gen-renamed-libs.sh /home/user/gen-renamed-libs.sh
RUN /bin/bash -c dos2unix /home/user/gen-renamed-libs.sh
RUN /bin/bash -c /home/user/gen-renamed-libs.sh

RUN sudo ln -snf /bin/bash /bin/sh

SHELL ["/bin/bash", "-c"]
