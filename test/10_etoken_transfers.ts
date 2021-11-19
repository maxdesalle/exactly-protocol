import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("EToken transfers", () => {
  let bob: SignerWithAddress;
  let laura: SignerWithAddress;
  let tito: SignerWithAddress;
  let eDAI: Contract;

  const { AddressZero } = ethers.constants;
  beforeEach(async () => {
    [bob, laura, tito] = await ethers.getSigners();

    const MockedEToken = await ethers.getContractFactory("EToken");
    eDAI = await MockedEToken.deploy("eFake DAI", "eFDAI");
    await eDAI.deployed();

    await eDAI.setFixedLender(bob.address); // We simulate that the address of user bob is the fixedLender contact
  });

  describe("GIVEN bob has 1000 eDAI AND transfers 500 eDAI to laura", () => {
    beforeEach(async () => {
      await eDAI.mint(bob.address, parseUnits("1000"));
      await eDAI.transfer(laura.address, parseUnits("500"));
    });

    it("THEN balance of eDAI in bob's address is 500", async () => {
      let bobBalance = await eDAI.balanceOf(bob.address);

      expect(bobBalance).to.equal(parseUnits("500"));
    });
    it("THEN balance of eDAI in laura's address is 500", async () => {
      let lauraBalance = await eDAI.balanceOf(laura.address);

      expect(lauraBalance).to.equal(parseUnits("500"));
    });
    it("THEN balance supply in contract is still 1000", async () => {
      let totalSupply = await eDAI.totalSupply();

      expect(totalSupply).to.equal(parseUnits("1000"));
    });
    it("AND WHEN bob transfers 100 eDAI more, THEN event Transfer is emitted", async () => {
      await expect(await eDAI.transfer(laura.address, parseUnits("100")))
        .to.emit(eDAI, "Transfer")
        .withArgs(bob.address, laura.address, parseUnits("100"));
    });
    it("AND WHEN bob transfers 100 eDAI to address zero, THEN it reverts with ERC20 transfer error", async () => {
      await expect(
        eDAI.transfer(AddressZero, parseUnits("100"))
      ).to.be.revertedWith("ERC20: transfer to the zero address");
    });
    describe("AND GIVEN an accrue of earnings by 1000 eDAI", () => {
      beforeEach(async () => {
        await eDAI.accrueEarnings(parseUnits("1000"));
      });

      it("THEN balance of eDAI in bob's address is 1000", async () => {
        let bobBalance = await eDAI.balanceOf(bob.address);

        expect(bobBalance).to.equal(parseUnits("1000"));
      });
      it("THEN balance of eDAI in laura's address is 1000", async () => {
        let lauraBalance = await eDAI.balanceOf(laura.address);

        expect(lauraBalance).to.equal(parseUnits("1000"));
      });
      it("THEN balance supply in contract is 2000", async () => {
        let totalSupply = await eDAI.totalSupply();

        expect(totalSupply).to.equal(parseUnits("2000"));
      });
      describe("AND GIVEN laura transfers 1000 eDAI to tito, AND GIVEN an accrue of earnings by 1000 eDAI", () => {
        beforeEach(async () => {
          await eDAI.connect(laura).transfer(tito.address, parseUnits("1000"));
          await eDAI.accrueEarnings(parseUnits("1000"));
        });

        it("THEN balance of eDAI in laura's address is 0", async () => {
          let lauraBalance = await eDAI.balanceOf(laura.address);

          expect(lauraBalance).to.equal(parseUnits("0"));
        });
        it("THEN balance of eDAI in tito's address is 1500", async () => {
          let titoBalance = await eDAI.balanceOf(tito.address);

          expect(titoBalance).to.equal(parseUnits("1500"));
        });
        it("THEN balance of eDAI in bob's address is 1500", async () => {
          let bobBalance = await eDAI.balanceOf(bob.address);

          expect(bobBalance).to.equal(parseUnits("1500"));
        });
        it("THEN balance supply in contract is 3000", async () => {
          let totalSupply = await eDAI.totalSupply();

          expect(totalSupply).to.equal(parseUnits("3000"));
        });
        describe("AND GIVEN bob transfers 1500 eDAI to tito, AND GIVEN 1000 eDAI more minted to tito, AND GIVEN an accrue of earnings by 1000 eDAI", () => {
          beforeEach(async () => {
            await eDAI.transfer(tito.address, parseUnits("1500"));
            await eDAI.mint(tito.address, parseUnits("1000"));
            await eDAI.accrueEarnings(parseUnits("1000"));
          });

          it("THEN balance of eDAI in tito's address is 5000", async () => {
            let titoBalance = await eDAI.balanceOf(tito.address);

            expect(titoBalance).to.equal(parseUnits("5000"));
          });
          it("THEN balance of eDAI in bob's address is 0", async () => {
            let bobBalance = await eDAI.balanceOf(bob.address);

            expect(bobBalance).to.equal(parseUnits("0"));
          });
          it("THEN balance of eDAI in laura's address is 0", async () => {
            let lauraBalance = await eDAI.balanceOf(laura.address);

            expect(lauraBalance).to.equal(parseUnits("0"));
          });
          it("THEN balance supply in contract is 5000", async () => {
            let totalSupply = await eDAI.totalSupply();

            expect(totalSupply).to.equal(parseUnits("5000"));
          });
          it("AND WHEN bob transfers more than his balance, THEN it reverts with ERC20 transfer exceeds balance error", async () => {
            await expect(
              eDAI.transfer(tito.address, parseUnits("100"))
            ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
          });
        });
      });
    });
  });
  describe("GIVEN bob allows tito to spend 500 eDAI AND he transfers 500 eDAI to laura", () => {
    beforeEach(async () => {
      await eDAI.mint(bob.address, parseUnits("1000"));
      await eDAI.approve(tito.address, parseUnits("500"));
      await eDAI
        .connect(tito)
        .transferFrom(bob.address, laura.address, parseUnits("500"));
    });

    it("THEN balance of eDAI in bob's address is 500", async () => {
      let bobBalance = await eDAI.balanceOf(bob.address);

      expect(bobBalance).to.equal(parseUnits("500"));
    });
    it("THEN balance of eDAI in laura's address is 500", async () => {
      let lauraBalance = await eDAI.balanceOf(laura.address);

      expect(lauraBalance).to.equal(parseUnits("500"));
    });
    it("THEN balance supply in contract is still 1000", async () => {
      let totalSupply = await eDAI.totalSupply();

      expect(totalSupply).to.equal(parseUnits("1000"));
    });
    it("AND WHEN tito transfers 100 eDAI more from bob, THEN it reverts with ERC20 allowance error", async () => {
      await expect(
        eDAI
          .connect(tito)
          .transferFrom(bob.address, laura.address, parseUnits("100"))
      ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
    });
    it("AND WHEN tito is allowed to spend 100 eDAI more from bob and transfers them, THEN event Transfer is emitted", async () => {
      await eDAI.approve(tito.address, parseUnits("100"));
      await expect(
        await eDAI
          .connect(tito)
          .transferFrom(bob.address, laura.address, parseUnits("100"))
      )
        .to.emit(eDAI, "Transfer")
        .withArgs(bob.address, laura.address, parseUnits("100"));
    });
    it("AND WHEN tito transfers 100 eDAI from bob to address zero, THEN it reverts with ERC20 transfer error", async () => {
      await expect(
        eDAI
          .connect(tito)
          .transferFrom(bob.address, AddressZero, parseUnits("100"))
      ).to.be.revertedWith("ERC20: transfer to the zero address");
    });
    describe("AND GIVEN an accrue of earnings by 1000 eDAI", () => {
      beforeEach(async () => {
        await eDAI.accrueEarnings(parseUnits("1000"));
      });

      it("THEN balance of eDAI in bob's address is 1000", async () => {
        let bobBalance = await eDAI.balanceOf(bob.address);

        expect(bobBalance).to.equal(parseUnits("1000"));
      });
      it("THEN balance of eDAI in laura's address is 1000", async () => {
        let lauraBalance = await eDAI.balanceOf(laura.address);

        expect(lauraBalance).to.equal(parseUnits("1000"));
      });
      it("THEN balance supply in contract is 2000", async () => {
        let totalSupply = await eDAI.totalSupply();

        expect(totalSupply).to.equal(parseUnits("2000"));
      });
      describe("AND GIVEN bob transfers 1000 eDAI from laura to tito, AND GIVEN an accrue of earnings by 1000 eDAI", () => {
        beforeEach(async () => {
          await eDAI.connect(laura).approve(bob.address, parseUnits("1000"));
          await eDAI
            .connect(bob)
            .transferFrom(laura.address, tito.address, parseUnits("1000"));
          await eDAI.accrueEarnings(parseUnits("1000"));
        });

        it("THEN balance of eDAI in laura's address is 0", async () => {
          let lauraBalance = await eDAI.balanceOf(laura.address);

          expect(lauraBalance).to.equal(parseUnits("0"));
        });
        it("THEN balance of eDAI in tito's address is 1500", async () => {
          let titoBalance = await eDAI.balanceOf(tito.address);

          expect(titoBalance).to.equal(parseUnits("1500"));
        });
        it("THEN balance of eDAI in bob's address is 1500", async () => {
          let bobBalance = await eDAI.balanceOf(bob.address);

          expect(bobBalance).to.equal(parseUnits("1500"));
        });
        it("THEN balance supply in contract is 3000", async () => {
          let totalSupply = await eDAI.totalSupply();

          expect(totalSupply).to.equal(parseUnits("3000"));
        });
        describe("AND GIVEN tito transfers 1500 eDAI from bob to him, AND GIVEN 1000 eDAI more minted to tito, AND GIVEN an accrue of earnings by 1000 eDAI", () => {
          beforeEach(async () => {
            await eDAI.approve(tito.address, parseUnits("1500"));
            await eDAI
              .connect(tito)
              .transferFrom(bob.address, tito.address, parseUnits("1500"));
            await eDAI.mint(tito.address, parseUnits("1000"));
            await eDAI.accrueEarnings(parseUnits("1000"));
          });

          it("THEN balance of eDAI in tito's address is 5000", async () => {
            let titoBalance = await eDAI.balanceOf(tito.address);

            expect(titoBalance).to.equal(parseUnits("5000"));
          });
          it("THEN balance of eDAI in bob's address is 0", async () => {
            let bobBalance = await eDAI.balanceOf(bob.address);

            expect(bobBalance).to.equal(parseUnits("0"));
          });
          it("THEN balance of eDAI in laura's address is 0", async () => {
            let lauraBalance = await eDAI.balanceOf(laura.address);

            expect(lauraBalance).to.equal(parseUnits("0"));
          });
          it("THEN balance supply in contract is 5000", async () => {
            let totalSupply = await eDAI.totalSupply();

            expect(totalSupply).to.equal(parseUnits("5000"));
          });
          it("AND WHEN tito transfers more than bob's balance, THEN it reverts with ERC20 transfer exceeds balance error", async () => {
            await eDAI.approve(tito.address, parseUnits("100"));
            await expect(
              eDAI
                .connect(tito)
                .transferFrom(bob.address, tito.address, parseUnits("100"))
            ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
          });
        });
      });
    });
  });
  describe("GIVEN bob allows tito to spend 500 eDAI AND he transfers 500 eDAI to laura", () => {
    beforeEach(async () => {
      await eDAI.mint(bob.address, parseUnits("1000"));
      await eDAI.approve(tito.address, parseUnits("500"));
      await eDAI
        .connect(tito)
        .transferFrom(bob.address, laura.address, parseUnits("500"));
    });

    it("THEN balance of eDAI in bob's address is 500", async () => {
      let bobBalance = await eDAI.balanceOf(bob.address);

      expect(bobBalance).to.equal(parseUnits("500"));
    });
    it("THEN balance of eDAI in laura's address is 500", async () => {
      let lauraBalance = await eDAI.balanceOf(laura.address);

      expect(lauraBalance).to.equal(parseUnits("500"));
    });
    it("THEN balance supply in contract is still 1000", async () => {
      let totalSupply = await eDAI.totalSupply();

      expect(totalSupply).to.equal(parseUnits("1000"));
    });
    it("AND WHEN tito transfers 100 eDAI more from bob, THEN it reverts with ERC20 allowance error", async () => {
      await expect(
        eDAI
          .connect(tito)
          .transferFrom(bob.address, laura.address, parseUnits("100"))
      ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
    });
    it("AND WHEN tito is allowed to spend 100 eDAI more from bob and transfers them, THEN event Transfer is emitted", async () => {
      await eDAI.approve(tito.address, parseUnits("100"));
      await expect(
        await eDAI
          .connect(tito)
          .transferFrom(bob.address, laura.address, parseUnits("100"))
      )
        .to.emit(eDAI, "Transfer")
        .withArgs(bob.address, laura.address, parseUnits("100"));
    });
    it("AND WHEN tito transfers 100 eDAI from bob to address zero, THEN it reverts with ERC20 transfer error", async () => {
      await expect(
        eDAI
          .connect(tito)
          .transferFrom(bob.address, AddressZero, parseUnits("100"))
      ).to.be.revertedWith("ERC20: transfer to the zero address");
    });
    describe("AND GIVEN an accrue of earnings by 1000 eDAI", () => {
      beforeEach(async () => {
        await eDAI.accrueEarnings(parseUnits("1000"));
      });

      it("THEN balance of eDAI in bob's address is 1000", async () => {
        let bobBalance = await eDAI.balanceOf(bob.address);

        expect(bobBalance).to.equal(parseUnits("1000"));
      });
      it("THEN balance of eDAI in laura's address is 1000", async () => {
        let lauraBalance = await eDAI.balanceOf(laura.address);

        expect(lauraBalance).to.equal(parseUnits("1000"));
      });
      it("THEN balance supply in contract is 2000", async () => {
        let totalSupply = await eDAI.totalSupply();

        expect(totalSupply).to.equal(parseUnits("2000"));
      });
      describe("AND GIVEN bob transfers 1000 eDAI from laura to tito, AND GIVEN an accrue of earnings by 1000 eDAI", () => {
        beforeEach(async () => {
          await eDAI.connect(laura).approve(bob.address, parseUnits("1000"));
          await eDAI
            .connect(bob)
            .transferFrom(laura.address, tito.address, parseUnits("1000"));
          await eDAI.accrueEarnings(parseUnits("1000"));
        });

        it("THEN balance of eDAI in laura's address is 0", async () => {
          let lauraBalance = await eDAI.balanceOf(laura.address);

          expect(lauraBalance).to.equal(parseUnits("0"));
        });
        it("THEN balance of eDAI in tito's address is 1500", async () => {
          let titoBalance = await eDAI.balanceOf(tito.address);

          expect(titoBalance).to.equal(parseUnits("1500"));
        });
        it("THEN balance of eDAI in bob's address is 1500", async () => {
          let bobBalance = await eDAI.balanceOf(bob.address);

          expect(bobBalance).to.equal(parseUnits("1500"));
        });
        it("THEN balance supply in contract is 3000", async () => {
          let totalSupply = await eDAI.totalSupply();

          expect(totalSupply).to.equal(parseUnits("3000"));
        });
        describe("AND GIVEN tito transfers 1500 eDAI from bob to him, AND GIVEN 1000 eDAI more minted to tito, AND GIVEN an accrue of earnings by 1000 eDAI", () => {
          beforeEach(async () => {
            await eDAI.approve(tito.address, parseUnits("1500"));
            await eDAI
              .connect(tito)
              .transferFrom(bob.address, tito.address, parseUnits("1500"));
            await eDAI.mint(tito.address, parseUnits("1000"));
            await eDAI.accrueEarnings(parseUnits("1000"));
          });

          it("THEN balance of eDAI in tito's address is 5000", async () => {
            let titoBalance = await eDAI.balanceOf(tito.address);

            expect(titoBalance).to.equal(parseUnits("5000"));
          });
          it("THEN balance of eDAI in bob's address is 0", async () => {
            let bobBalance = await eDAI.balanceOf(bob.address);

            expect(bobBalance).to.equal(parseUnits("0"));
          });
          it("THEN balance of eDAI in laura's address is 0", async () => {
            let lauraBalance = await eDAI.balanceOf(laura.address);

            expect(lauraBalance).to.equal(parseUnits("0"));
          });
          it("THEN balance supply in contract is 5000", async () => {
            let totalSupply = await eDAI.totalSupply();

            expect(totalSupply).to.equal(parseUnits("5000"));
          });
          it("AND WHEN tito transfers more than bob's balance, THEN it reverts with ERC20 transfer exceeds balance error", async () => {
            await eDAI.approve(tito.address, parseUnits("100"));
            await expect(
              eDAI
                .connect(tito)
                .transferFrom(bob.address, tito.address, parseUnits("100"))
            ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
          });
        });
      });
    });
  });
});
